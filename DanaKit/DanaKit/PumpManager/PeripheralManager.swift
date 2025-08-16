import CoreBluetooth
import os.log
import SwiftUI

class PeripheralManager: NSObject {
    private let log = DanaLogger(category: "PeripheralManager")

    private let connectedDevice: CBPeripheral
    private let bluetoothManager: BluetoothManager
    private var completion: ((ConnectionResult) -> Void)?

    private var pumpManager: DanaKitPumpManager
    private var readBuffer = Data([])

    private let okCharCodes: [UInt8] = [0x4F, 0x4B] // O, K
    private let pumpCharCodes: [UInt8] = [0x50, 0x55, 0x4D, 0x50] // P, U, M, P
    private let busyCharCodes: [UInt8] = [0x42, 0x55, 0x53, 0x59] // B, U, S, Y

    private let PACKET_START_BYTE: UInt8 = 0xA5
    private let PACKET_END_BYTE: UInt8 = 0x5A
    private let ENCRYPTED_START_BYTE: UInt8 = 0xAA
    private let ENCRYPTED_END_BYTE: UInt8 = 0xEE

    public static let SERVICE_UUID = CBUUID(string: "FFF0")
    private let READ_CHAR_UUID = CBUUID(string: "FFF1")
    private var readCharacteristic: CBCharacteristic?
    private let WRITE_CHAR_UUID = CBUUID(string: "FFF2")
    private var writeCharacteristic: CBCharacteristic?

    private var writeQueue: [UInt8: AsyncThrowingStream<any DanaParsePacketProtocol, Error>.Continuation] = [:]
    private var writeTimeoutTask: Task<Void, Never>?
    private let writeSemaphore = DispatchSemaphore(value: 1)

    private var historyLog: [HistoryItem] = []

    private var deviceName: String {
        pumpManager.state.deviceName ?? ""
    }

    public init(
        _ peripheral: CBPeripheral,
        _ bluetoothManager: BluetoothManager,
        _ pumpManager: DanaKitPumpManager,
        _ completion: @escaping (ConnectionResult) -> Void
    ) {
        connectedDevice = peripheral
        self.bluetoothManager = bluetoothManager
        self.pumpManager = pumpManager
        self.completion = completion

        super.init()

        peripheral.delegate = self
    }

    deinit {
        self.writeTimeoutTask?.cancel()

        for (opCode, stream) in self.writeQueue {
            stream.finish()
        }
    }

    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol) {
        guard writeQueue[packet.opCode] == nil else {
            throw NSError(domain: "Command already running", code: 0, userInfo: nil)
        }

        let stream = AsyncThrowingStream<any DanaParsePacketProtocol, Error> { continuation in
            writeQueue[packet.opCode] = continuation
            self.write(packet)
        }

        return try await firstValue(from: stream)
    }

    private func firstValue(from stream: AsyncThrowingStream<any DanaParsePacketProtocol, Error>) async throws
        -> (any DanaParsePacketProtocol)
    {
        for try await value in stream {
            return value
        }
        throw NSError(domain: "Got no response. Most likely an encryption issue", code: 0, userInfo: nil)
    }

    private func write(_ packet: DanaGeneratePacket) {
        writeSemaphore.wait()

        let command = (UInt16(packet.type ?? DanaPacketType.TYPE_RESPONSE) << 8) + UInt16(packet.opCode)

        // Make sure we have the correct state
        if packet.opCode == CommandGeneralSetHistoryUploadMode, packet.data != nil {
            pumpManager.state.isInFetchHistoryMode = packet.data![0] == 0x01
        } else {
            pumpManager.state.isInFetchHistoryMode = false
        }

        var data = DanaRSEncryption.encodePacket(operationCode: packet.opCode, buffer: packet.data, deviceName: deviceName)
        log
            .debug(
                "Sending opCode: \(packet.opCode), encrypted data: \(data.base64EncodedString()), randomSyncKey: \(DanaRSEncryption.randomSyncKey)"
            )

        if DanaRSEncryption.enhancedEncryption != EncryptionType.DEFAULT.rawValue {
            data = DanaRSEncryption.encodeSecondLevel(data: data)
            log.debug("Second level encrypted data: \(data.base64EncodedString())")
        }

        // Now schedule a 6 sec timeout (or 21 when in fetchHistoryMode) for the pump to send its message back
        // This timeout will be cancelled by `processMessage` once it received the message
        // If this timeout expired, disconnect from the pump and prompt an error...
        let isHistoryPacket = self.isHistoryPacket(opCode: command)
        while !data.isEmpty {
            let end = min(20, data.count)
            let message = data.subdata(in: 0 ..< end)

            writeQ(message)
            data = data.subdata(in: end ..< data.count)
        }

        writeTimeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(!isHistoryPacket ? .seconds(4) : .seconds(21)) * 1_000_000_000)
                guard let stream = self.writeQueue[packet.opCode] else {
                    // We did what we must, so exist and be happy :)
                    return
                }

                // We hit a timeout
                // This means the pump received the message but could decrypt it
                // We need to reconnect in order to fix the encryption keys
                self.bluetoothManager.manager.cancelPeripheralConnection(self.connectedDevice)
                stream.finish()

                self.writeQueue.removeValue(forKey: packet.opCode)
                self.writeTimeoutTask = nil
                self.writeSemaphore.signal()
            } catch {
                // Task was cancelled because message has been received
            }
        }
    }

    private func connectionFailure(_ error: any Error) {
        bluetoothManager.manager.cancelPeripheralConnection(connectedDevice)

        guard let completion = self.completion else {
            return
        }

        DispatchQueue.main.async {
            completion(.failure(error))
        }
    }
}

extension PeripheralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }

        let service = peripheral.services?.first(where: { $0.uuid == PeripheralManager.SERVICE_UUID })
        if service == nil {
            log.error("Failed to discover dana data service...")
            connectionFailure(NSError(domain: "Failed to discover dana data service...", code: 0, userInfo: nil))
            return
        }

        log.debug("Discovered service \(PeripheralManager.SERVICE_UUID)")
        peripheral.discoverCharacteristics([READ_CHAR_UUID, WRITE_CHAR_UUID], for: service!)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }

        let service = peripheral.services!.first(where: { $0.uuid == PeripheralManager.SERVICE_UUID })!
        readCharacteristic = service.characteristics?.first(where: { $0.uuid == READ_CHAR_UUID })
        writeCharacteristic = service.characteristics?.first(where: { $0.uuid == WRITE_CHAR_UUID })

        guard writeCharacteristic != nil, let readCharacteristic = readCharacteristic else {
            log.error("Failed to discover dana write or read characteristic")
            connectionFailure(NSError(domain: "Failed to discover dana write or read characteristic", code: 0, userInfo: nil))
            return
        }

        log.debug("Discovered characteristics \(READ_CHAR_UUID) and \(WRITE_CHAR_UUID)")
        peripheral.setNotifyValue(true, for: readCharacteristic)
    }

    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor _: CBCharacteristic, error: Error?) {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }

        log.debug("Notifications has been enabled. Sending starting handshake")
        sendFirstMessageEncryption()
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }

        guard let data = characteristic.value else {
            return
        }

        log.debug("Receiving data: \(data.base64EncodedString())")
        parseReceivedValue(data)
    }

    private func writeQ(_ data: Data) {
        guard let writeCharacteristic = writeCharacteristic else {
            log.error("No write characteristic available. Device might be disconnected...")
            return
        }

        log.debug("Writing data \(data.base64EncodedString())")
        connectedDevice.writeValue(data, for: writeCharacteristic, type: .withoutResponse)
    }
}

// MARK: - Encryption/Connection functions

extension PeripheralManager {
    private func sendFirstMessageEncryption() {
        let data = DanaRSEncryption.encodePacket(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__PUMP_CHECK,
            buffer: nil,
            deviceName: deviceName
        )

        log.debug("Sending Initial encryption request. Data: \(data.base64EncodedString())")
        writeQ(data)
    }

    private func sendTimeInfo() {
        let data = DanaRSEncryption.encodePacket(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION,
            buffer: nil,
            deviceName: deviceName
        )

        log.debug("Sending normal time information. Data: \(data.base64EncodedString())")
        writeQ(data)
    }

    private func sendV3PairingInformation(_ requestNewPairing: UInt8) {
        let data = DanaRSEncryption.encodePacket(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION,
            buffer: Data([requestNewPairing]),
            deviceName: deviceName
        )

        log.debug("Sending RSv3 time information. Data: \(data.base64EncodedString())")
        writeQ(data)
    }

    // 0x00 Start encryption, 0x01 Request pairing
    private func sendV3PairingInformationEmpty() {
        var (pairingKey, randomPairingKey) = DanaRSEncryption.getPairingKeys()
        if pairingKey.filter({ $0 != 0 }).isEmpty || randomPairingKey.filter({ $0 != 0 }).isEmpty {
            pairingKey = pumpManager.state.pairingKey
            randomPairingKey = pumpManager.state.randomPairingKey

            if pairingKey.filter({ $0 != 0 }).isEmpty || randomPairingKey.filter({ $0 != 0 }).isEmpty {
                sendV3PairingInformation(1)
                return
            }
        }

        let randomSyncKey = pumpManager.state.randomSyncKey
        log
            .debug(
                "Setting encryption keys. Pairing key: \(pairingKey.base64EncodedString()), random pairing key: \(randomPairingKey.base64EncodedString()), random sync key: \(randomSyncKey)"
            )
        DanaRSEncryption.setPairingKeys(pairingKey: pairingKey, randomPairingKey: randomPairingKey, randomSyncKey: randomSyncKey)

        sendV3PairingInformation(0)
    }

    private func sendPairingRequest() {
        let data = DanaRSEncryption.encodePacket(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__PASSKEY_REQUEST,
            buffer: nil,
            deviceName: deviceName
        )

        log.debug("Sending pairing request. Data: \(data.base64EncodedString())")
        writeQ(data)
    }

    private func sendEasyMenuCheck() {
        let data = DanaRSEncryption.encodePacket(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__GET_EASYMENU_CHECK,
            buffer: nil,
            deviceName: deviceName
        )

        log.debug("Sending easy menu check. Data: \(data.base64EncodedString())")
        writeQ(data)
    }

    private func sendBLE5PairingInformation() {
        let data = DanaRSEncryption.encodePacket(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION,
            buffer: Data([0, 0, 0, 0]),
            deviceName: deviceName
        )

        log.debug("Sending BLE5 time information. Data: \(Data([0, 0, 0, 0]).base64EncodedString())")
        writeQ(data)
    }

    private func sendPassKeyCheck(_ pairingKey: Data) {
        let data = DanaRSEncryption.encodePacket(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__CHECK_PASSKEY,
            buffer: pairingKey,
            deviceName: deviceName
        )

        log.debug("Sending Passkey check. Data: \(data.base64EncodedString())")
        writeQ(data)
    }

    /// Used after entering PIN codes (only for DanaRS v3)
    public func finishV3Pairing(_ pairingKey: Data, _ randomPairingKey: Data) {
        log
            .debug(
                "Storing security keys: Pairing key: \(pairingKey.base64EncodedString()), random pairing key: \(randomPairingKey.base64EncodedString())"
            )

        DanaRSEncryption.setPairingKeys(pairingKey: pairingKey, randomPairingKey: randomPairingKey, randomSyncKey: nil)
        pumpManager.state.pairingKey = pairingKey
        pumpManager.state.randomPairingKey = randomPairingKey

        sendV3PairingInformation(0)
    }

    private func processEasyMenuCheck(_: Data) {
        if DanaRSEncryption.enhancedEncryption == EncryptionType.RSv3.rawValue {
            sendV3PairingInformationEmpty()
        } else {
            sendTimeInfo()
        }
    }

    private func processPairingRequest(_ data: Data) {
        if data[2] == 0x00 {
            // Everything is order. Waiting for pump to send OPCODE_ENCRYPTION__PASSKEY_RETURN
            return
        }

        log.error("Passkey request failed. Data: \(data.base64EncodedString())")
        connectionFailure(NSError(domain: "Passkey request failed", code: 0, userInfo: nil))
    }

    private func processPairingRequest2(_ data: Data) {
        sendTimeInfo()

        let pairingKey = data.subdata(in: 2 ..< 4)
        DanaRSEncryption.setPairingKeys(pairingKey: pairingKey, randomPairingKey: Data(), randomSyncKey: 0)
    }

    private func processConnectResponse(_ data: Data) {
        if data.count == 4, isOk(data) {
            // response OK v1
            log.info("Setting encryption mode to DEFAULT")
            DanaRSEncryption.setEnhancedEncryption(EncryptionType.DEFAULT.rawValue)

            pumpManager.state.ignorePassword = false

            let (pairingKey, _) = DanaRSEncryption.getPairingKeys()
            if !pairingKey.isEmpty {
                sendPassKeyCheck(pairingKey)
            } else {
                sendPairingRequest()
            }
        } else if data.count == 9, isOk(data) {
            // response OK v3, 2nd layer encryption
            log.info("Setting encryption mode to RSv3")
            DanaRSEncryption.setEnhancedEncryption(EncryptionType.RSv3.rawValue)

            pumpManager.state.ignorePassword = true

            pumpManager.state.hwModel = data[5]
            pumpManager.state.pumpProtocol = data[7]

            // Grab syncKey
            pumpManager.state.randomSyncKey = data[data.count - 1]

            if pumpManager.state.hwModel == 0x05 {
                sendV3PairingInformationEmpty()
            } else if pumpManager.state.hwModel == 0x06 {
                sendEasyMenuCheck()
            } else {
                log.error("Got invalid hwModel \(pumpManager.state.hwModel)")
                connectionFailure(NSError(domain: "Invalid hwModel", code: 0, userInfo: nil))
            }
        } else if data.count == 14, isOk(data) {
            log.info("Setting encryption mode to BLE5")
            DanaRSEncryption.setEnhancedEncryption(EncryptionType.BLE_5.rawValue)

            pumpManager.state.hwModel = data[5]
            pumpManager.state.pumpProtocol = data[7]

            guard pumpManager.state.hwModel == 0x09 || pumpManager.state.hwModel == 0x0A else {
                log.error("Got invalid hwModel \(pumpManager.state.hwModel)")
                connectionFailure(NSError(domain: "Invalid hwModel", code: 0, userInfo: nil))
                return
            }

            var ble5Keys = data.subdata(in: 8 ..< 14)
            if !ble5Keys.filter({ $0 == 0 }).isEmpty {
                // Try to get keys from previous session
                ble5Keys = pumpManager.state.ble5Keys
            }

            guard ble5Keys.filter({ $0 == 0 }).isEmpty else {
                log.error("Invalid BLE-5 keys. Please unbound device and try again.")

                bluetoothManager.manager.cancelPeripheralConnection(connectedDevice)
                guard let completion = self.completion else {
                    return
                }

                completion(.invalidBle5Keys)
                return
            }

            DanaRSEncryption.setBle5Key(ble5Key: ble5Keys)
            pumpManager.state.ble5Keys = ble5Keys
            sendBLE5PairingInformation()
        } else if data.count == 6, isPump(data) {
            log.error("PUMP_CHECK error. Data: \(data.base64EncodedString())")
            connectionFailure(NSError(domain: "PUMP_CHECK error", code: 0, userInfo: nil))
        } else if data.count == 6, isBusy(data) {
            log.error("PUMP_CHECK_BUSY error. Data: \(data.base64EncodedString())")
            connectionFailure(NSError(domain: "PUMP_CHECK_BUSY error", code: 0, userInfo: nil))
        } else {
            log.error("PUMP_CHECK error, wrong serial number. Data: \(data.base64EncodedString())")
            connectionFailure(NSError(domain: "PUMP_CHECK error, wrong serial number", code: 0, userInfo: nil))
        }
    }

    private func processEncryptionResponse(_ data: Data) {
        if DanaRSEncryption.enhancedEncryption == EncryptionType.BLE_5.rawValue {
            finishConnection()

        } else if DanaRSEncryption.enhancedEncryption == EncryptionType.RSv3.rawValue {
            // data[2] : 0x00 OK  0x01 Error, No pairing
            if data[2] == 0x00 {
                let (pairingKey, randomPairingKey) = DanaRSEncryption.getPairingKeys()
                if pairingKey.isEmpty || randomPairingKey.isEmpty {
                    log.debug("Device is requesting pincode")
                    promptPincode(nil)
                    return
                }

                finishConnection()
            } else {
                sendV3PairingInformation(1)
            }
        } else {
            let highByte = UInt16((data[data.count - 1] & 0xFF) << 8)
            let lowByte = UInt16(data[data.count - 2] & 0xFF)
            let password = (highByte + lowByte) ^ 0x0D87
            if password != pumpManager.state.devicePassword, !pumpManager.state.ignorePassword {
                log.error("Invalid password")
                connectionFailure(NSError(domain: "Invalid password", code: 0, userInfo: nil))
                return
            }

            finishConnection()
        }
    }

    private func finishConnection() {
        pumpManager.state.isConnected = true
        log.info("Connection and encryption successful!")

        DispatchQueue.main.async {
            self.completion?(.success)
            self.completion = nil
        }
    }

    private func promptPincode(_ errorMessage: String?) {
        guard let completion = self.completion else {
            return
        }

        completion(.requestedPincode(errorMessage))
    }

    private func isOk(_ data: Data) -> Bool {
        data[2] == okCharCodes[0] && data[3] == okCharCodes[1]
    }

    private func isPump(_ data: Data) -> Bool {
        data[2] == pumpCharCodes[0] && data[3] == pumpCharCodes[1] && data[4] == pumpCharCodes[2] && data[5] == pumpCharCodes[3]
    }

    private func isBusy(_ data: Data) -> Bool {
        data[2] == busyCharCodes[0] && data[3] == busyCharCodes[1] && data[4] == busyCharCodes[2] && data[5] == busyCharCodes[3]
    }
}

// MARK: Parsers for incomming messages

extension PeripheralManager {
    private func parseReceivedValue(_ receievedData: Data) {
        var data = receievedData
        if !data.isEmpty && pumpManager.state.isConnected && DanaRSEncryption.enhancedEncryption != EncryptionType.DEFAULT
            .rawValue
        {
            log.debug("Second lvl decryption")
            data = DanaRSEncryption.decodeSecondLevel(data: data)
        }

        readBuffer.append(data)
        guard readBuffer.count >= 6 else {
            // Buffer is not ready to be processed
            return
        }

        if
            !(readBuffer[0] == PACKET_START_BYTE || readBuffer[0] == ENCRYPTED_START_BYTE) ||
            !(readBuffer[1] == PACKET_START_BYTE || readBuffer[1] == ENCRYPTED_START_BYTE)
        {
            // The buffer does not start with the opening bytes. Check if the buffer is filled with old data
            if let indexStartByte = readBuffer.firstIndex(of: PACKET_START_BYTE) {
                readBuffer = readBuffer.subdata(in: indexStartByte ..< readBuffer.count)
            } else if let indexEncryptedStartByte = readBuffer.firstIndex(of: ENCRYPTED_START_BYTE) {
                readBuffer = readBuffer.subdata(in: indexEncryptedStartByte ..< readBuffer.count)
            } else {
                log
                    .error(
                        "Received invalid packets. Starting bytes do not exists in message. Encryption mode possibly wrong Data: \(readBuffer.base64EncodedString())"
                    )
                readBuffer = Data([])
                bluetoothManager.manager.cancelPeripheralConnection(connectedDevice)
                return
            }
        }

        let length = Int(readBuffer[2])
        guard length + 7 == readBuffer.count else {
            // Not all packets have been received yet...
            log.debug("Not all packets have been received yet - Should be: \(length + 7), currently: \(readBuffer.count)")
            return
        }

        guard
            (readBuffer[length + 5] == PACKET_END_BYTE || readBuffer[length + 5] == ENCRYPTED_END_BYTE) &&
            (readBuffer[length + 6] == PACKET_END_BYTE || readBuffer[length + 6] == ENCRYPTED_END_BYTE)
        else {
            // Invalid packets received...
            log.error("Received invalid packets. Ending bytes do not match. Data: \(readBuffer.base64EncodedString())")
            readBuffer = Data([])
            return
        }

        log.debug("Received message! Starting to decrypt data: \(readBuffer.base64EncodedString())")
        let decryptedData = DanaRSEncryption.decodePacket(buffer: readBuffer, deviceName: deviceName)
        readBuffer = Data([])

        guard !decryptedData.isEmpty else {
            log.error("Decryption failed...")
            return
        }

        log.debug("Decoding successful! Data: \(decryptedData.base64EncodedString())")
        if decryptedData[0] == DanaPacketType.TYPE_ENCRYPTION_RESPONSE {
            switch decryptedData[1] {
            case DanaPacketType.OPCODE_ENCRYPTION__PUMP_CHECK:
                processConnectResponse(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION:
                processEncryptionResponse(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__CHECK_PASSKEY:
                if decryptedData[2] == 0x05 {
                    sendTimeInfo()
                } else {
                    sendPairingRequest()
                }
                return
            case DanaPacketType.OPCODE_ENCRYPTION__PASSKEY_REQUEST:
                processPairingRequest(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__PASSKEY_RETURN:
                processPairingRequest2(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__GET_PUMP_CHECK:
                if decryptedData[2] == 0x05 {
                    sendTimeInfo()
                } else {
                    sendEasyMenuCheck()
                }
                return
            case DanaPacketType.OPCODE_ENCRYPTION__GET_EASYMENU_CHECK:
                processEasyMenuCheck(decryptedData)
                return
            default:
                log.error("Received invalid encryption command type \(decryptedData[1])")
                return
            }
        }

        guard decryptedData[0] == DanaPacketType.TYPE_RESPONSE || decryptedData[0] == DanaPacketType.TYPE_NOTIFY else {
            log.error("Received invalid packet type \(decryptedData[0])")
            return
        }

        processMessage(decryptedData)
    }

    private func processMessage(_ data: Data) {
        let message = parseMessage(data: data, usingUtc: pumpManager.state.usingUtc)
        guard let message = message else {
            log.error("Received unparsable message. Data: \(data.base64EncodedString())")
            return
        }

        if message.notifyType != nil {
            switch message.notifyType {
            case CommandNotifyDeliveryComplete:
                let data = message.data as! PacketNotifyDeliveryComplete
                pumpManager.notifyBolusDone(deliveredUnits: data.deliveredInsulin)
                return
            case CommandNotifyDeliveryRateDisplay:
                let data = message.data as! PacketNotifyDeliveryRateDisplay
                pumpManager.notifyBolusDidUpdate(deliveredUnits: data.deliveredInsulin)
                return
            case CommandNotifyAlarm:
                let data = message.data as! PacketNotifyAlarm
                pumpManager.notifyBolusError()
                pumpManager.notifyAlert(data.alert)
                return
            default:
                pumpManager.notifyBolusError()
                return
            }
        }

        // Message received and dequeueing timeout
        guard let opCode = message.opCode, let stream = writeQueue[opCode] else {
            log.error("No stream found to send this message back...")
            writeSemaphore.signal()
            return
        }

        if let data = message.data as? HistoryItem {
            if data.code == HistoryCode.RECORD_TYPE_DONE_UPLOAD {
                stream.yield(DanaParsePacket<[HistoryItem]>(
                    success: true,
                    rawData: Data([]),
                    data: historyLog.map({ $0 })
                ))
                stream.finish()

                writeQueue.removeValue(forKey: opCode)
                writeTimeoutTask?.cancel()
                writeTimeoutTask = nil
                historyLog = []
                writeSemaphore.signal()
            } else {
                historyLog.append(data)
            }

            return
        }

        stream.yield(message)
        stream.finish()

        writeQueue.removeValue(forKey: opCode)
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil
        writeSemaphore.signal()
    }

    private func isHistoryPacket(opCode: UInt16) -> Bool {
        opCode > CommandHistoryBolus && opCode < CommandHistoryAll
    }
}
