//
//  PeripheralManager+RileyLink.swift
//  xDripG5
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import os.log


protocol CBUUIDRawValue: RawRepresentable {}
extension CBUUIDRawValue where RawValue == String {
    var cbUUID: CBUUID {
        return CBUUID(string: rawValue.uppercased())
    }
}


enum RileyLinkServiceUUID: String, CBUUIDRawValue {
    case main
            = "0235733B-99C5-4197-B856-69219C2A3845"
    case battery   = "180F"
    case orange    = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    case secureDFU = "FE59"
}

enum MainServiceCharacteristicUUID: String, CBUUIDRawValue {
    case data            = "C842E849-5028-42E2-867C-016ADADA9155"
    case responseCount   = "6E6C7910-B89E-43A5-A0FE-50C5E2B81F4A"
    case customName      = "D93B2AF0-1E28-11E4-8C21-0800200C9A66"
    case timerTick       = "6E6C7910-B89E-43A5-78AF-50C5E2B86F7E"
    case firmwareVersion = "30D99DC9-7C91-4295-A051-0A104D238CF2"
    case ledMode         = "C6D84241-F1A7-4F9C-A25F-FCE16732F14E"
}

enum BatteryServiceCharacteristicUUID: String, CBUUIDRawValue {
    case battery_level   = "2A19"
}

enum OrangeServiceCharacteristicUUID: String, CBUUIDRawValue {
    case orangeRX = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    case orangeTX = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}

enum SecureDFUCharacteristicUUID: String, CBUUIDRawValue {
    case control = "8EC90001-F315-4F60-9FB8-838830DAEA50"
}


public enum OrangeLinkCommand: UInt8 {
    case yellow   = 0x1
    case red      = 0x2
    case off      = 0x3
    case shake    = 0x4
    case shakeOff = 0x5
    case fw_hw    = 0x9
}

public enum OrangeLinkRequestType: UInt8 {
    case fctStartLoop = 0xaa // Fct_StartLoop
    case fctHeader = 0xbb    // Fct_PutReq
    case fctStopLoop = 0xcc  // Fct_StopLoop
    case cfgHeader = 0xdd    // Cfg_PutReq
}

public enum OrangeLinkConfigurationSetting: UInt8 {
    case connectionLED     = 0x00
    case connectionVibrate = 0x01
}

public enum RileyLinkLEDMode: UInt8 {
    case off  = 0x00
    case on   = 0x01
    case auto = 0x02
}


extension PeripheralManager.Configuration {
    static var rileyLink: PeripheralManager.Configuration {
        return PeripheralManager.Configuration(
            serviceCharacteristics: [
                RileyLinkServiceUUID.main.cbUUID: [
                    MainServiceCharacteristicUUID.data.cbUUID,
                    MainServiceCharacteristicUUID.responseCount.cbUUID,
                    MainServiceCharacteristicUUID.customName.cbUUID,
                    MainServiceCharacteristicUUID.timerTick.cbUUID,
                    MainServiceCharacteristicUUID.firmwareVersion.cbUUID,
                    MainServiceCharacteristicUUID.ledMode.cbUUID
                ],
                RileyLinkServiceUUID.battery.cbUUID: [
                    BatteryServiceCharacteristicUUID.battery_level.cbUUID
                ],
                RileyLinkServiceUUID.orange.cbUUID: [
                    OrangeServiceCharacteristicUUID.orangeRX.cbUUID,
                    OrangeServiceCharacteristicUUID.orangeTX.cbUUID,
                ],
                RileyLinkServiceUUID.secureDFU.cbUUID: [
                    SecureDFUCharacteristicUUID.control.cbUUID,
                ]

            ],
            notifyingCharacteristics: [
                RileyLinkServiceUUID.main.cbUUID: [
                    MainServiceCharacteristicUUID.responseCount.cbUUID
                ],
                RileyLinkServiceUUID.orange.cbUUID: [
                    OrangeServiceCharacteristicUUID.orangeTX.cbUUID,
                ]
            ],
            valueUpdateMacros: [
                // When the responseCount changes, the data characteristic should be read.
                MainServiceCharacteristicUUID.responseCount.cbUUID: { (manager: PeripheralManager) in
                    log.debug("responseCount valueUpdated")
                    guard let dataCharacteristic = manager.peripheral.getCharacteristicWithUUID(.data)
                    else {
                        log.debug("could not get data characteristic")
                        return
                    }
                    log.debug("Reading data characteristic")
                    manager.peripheral.readValue(for: dataCharacteristic)
                }
            ]
        )
    }
}

fileprivate extension CBPeripheral {
    func getBatteryCharacteristic(_ uuid: BatteryServiceCharacteristicUUID) -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(RileyLinkServiceUUID.battery.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(uuid.cbUUID)
    }
    
    func getOrangeCharacteristic(_ uuid: OrangeServiceCharacteristicUUID) -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(RileyLinkServiceUUID.orange.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(uuid.cbUUID)
    }
    
    func getCharacteristicWithUUID(_ uuid: MainServiceCharacteristicUUID, serviceUUID: RileyLinkServiceUUID = .main) -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(serviceUUID.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(uuid.cbUUID)
    }
}


extension CBCentralManager {
    func scanForPeripherals(withOptions options: [String: Any]? = nil) {
        scanForPeripherals(withServices: [RileyLinkServiceUUID.main.cbUUID], options: options)
    }
}


extension Command {
    /// Encodes a command's data by validating and prepending its length
    ///
    /// - Returns: Writable command data
    /// - Throws: RileyLinkDeviceError.writeSizeLimitExceeded if the command data is too long
    fileprivate func writableData() throws -> Data {
        var data = self.data

        guard data.count <= 220 else {
            throw RileyLinkDeviceError.writeSizeLimitExceeded(maxLength: 220)
        }

        data.insert(UInt8(clamping: data.count), at: 0)
        return data
    }
}


private let log = OSLog(category: "PeripheralManager+RileyLink")


extension PeripheralManager {
    static let expectedMaxBLELatency: TimeInterval = 2
    
    func readBatteryLevel(completion: @escaping (Int?) -> Void) {
        perform { (manager) in
            guard let characteristic = self.peripheral.getBatteryCharacteristic(.battery_level) else {
                completion(nil)
                return
            }
            
            do {
                guard let data = try self.readValue(for: characteristic, timeout: PeripheralManager.expectedMaxBLELatency) else {
                    completion(nil)
                    return
                }
                
                completion(Int(data[0]))
            } catch {
                completion(nil)
            }
        }
    }
    
    func readDiagnosticLEDMode(completion: @escaping (RileyLinkLEDMode?) -> Void) {
        perform { (manager) in
            do {
                guard
                    let characteristic = self.peripheral.getCharacteristicWithUUID(.ledMode),
                    let data = try self.readValue(for: characteristic, timeout: PeripheralManager.expectedMaxBLELatency),
                    let mode = RileyLinkLEDMode(rawValue: data[0]) else
                {
                    completion(nil)
                    return
                }
                completion(mode)
            } catch {
                completion(nil)
            }
        }
    }

    var timerTickEnabled: Bool {
        return peripheral.getCharacteristicWithUUID(.timerTick)?.isNotifying ?? false
    }

    func setTimerTickEnabled(_ enabled: Bool, timeout: TimeInterval = expectedMaxBLELatency, completion: ((_ error: RileyLinkDeviceError?) -> Void)? = nil) {
        perform { (manager) in
            do {
                guard let characteristic = manager.peripheral.getCharacteristicWithUUID(.timerTick) else {
                    throw PeripheralManagerError.unknownCharacteristic(MainServiceCharacteristicUUID.timerTick.cbUUID)
                }

                try manager.setNotifyValue(enabled, for: characteristic, timeout: timeout)
                completion?(nil)
            } catch let error as PeripheralManagerError {
                completion?(.peripheralManagerError(error))
            } catch {
                assertionFailure()
            }
        }
    }

    func setLEDMode(mode: RileyLinkLEDMode) {
        perform { (manager) in
            do {
                guard let characteristic = manager.peripheral.getCharacteristicWithUUID(.ledMode) else {
                    throw PeripheralManagerError.unknownCharacteristic(MainServiceCharacteristicUUID.ledMode.cbUUID)
                }
                let value = Data([mode.rawValue])
                try manager.writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (let error) {
                assertionFailure(String(describing: error))
            }
        }
    }

    

    func startIdleListening(idleTimeout: TimeInterval, channel: UInt8, timeout: TimeInterval = expectedMaxBLELatency, completion: @escaping (_ error: RileyLinkDeviceError?) -> Void) {
        perform { (manager) in
            let command = GetPacket(listenChannel: channel, timeoutMS: UInt32(clamping: Int(idleTimeout.milliseconds)))

            do {
                try manager.writeCommandWithoutResponse(command, timeout: timeout)
                completion(nil)
            } catch let error as RileyLinkDeviceError {
                completion(error)
            } catch {
                assertionFailure()
            }
        }
    }

    func setCustomName(_ name: String, timeout: TimeInterval = expectedMaxBLELatency, completion: ((_ error: RileyLinkDeviceError?) -> Void)? = nil) {
        guard let value = name.data(using: .utf8) else {
            completion?(.errorResponse(name))
            return
        }

        perform { (manager) in
            do {
                guard let characteristic = manager.peripheral.getCharacteristicWithUUID(.customName) else {
                    throw PeripheralManagerError.unknownCharacteristic(MainServiceCharacteristicUUID.customName.cbUUID)
                }

                try manager.writeValue(value, for: characteristic, type: .withResponse, timeout: timeout)
                completion?(nil)
            } catch let error as PeripheralManagerError {
                completion?(.peripheralManagerError(error))
            } catch {
                assertionFailure()
            }
        }
    }
}



// MARK: - Synchronous commands
extension PeripheralManager {
    enum ResponseType {
        case single
        case buffered
    }

    /// Invokes a command expecting a response
    ///
    /// - Parameters:
    ///   - command: The command
    ///   - timeout: The amount of time to wait for the peripheral to respond before throwing a timeout error
    ///   - responseType: The BLE response value framing method
    /// - Returns: The received response
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    ///     - RileyLinkDeviceError.writeSizeLimitExceeded
    func writeCommand<C: Command>(_ command: C, timeout: TimeInterval, responseType: ResponseType) throws -> C.ResponseType {
        guard let characteristic = peripheral.getCharacteristicWithUUID(.data) else {
            throw RileyLinkDeviceError.peripheralManagerError(PeripheralManagerError.unknownCharacteristic(MainServiceCharacteristicUUID.data.cbUUID))
        }

        let value = try command.writableData()


        switch responseType {
        case .single:
            log.debug("RL Send (single): %@", value.hexadecimalString)
            return try writeCommand(value,
                for: characteristic,
                timeout: timeout
            )
        case .buffered:
            log.debug("RL Send (buffered): %@", value.hexadecimalString)
            return try writeLegacyCommand(value,
                for: characteristic,
                timeout: timeout,
                endOfResponseMarker: 0x00
            )
        }
    }

    /// Invokes a command without waiting for its response
    ///
    /// - Parameters:
    ///   - command: The command
    ///   - timeout: The amount of time to wait for the peripheral to confirm the write before throwing a timeout error
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    ///     - RileyLinkDeviceError.writeSizeLimitExceeded
    fileprivate func writeCommandWithoutResponse<C: Command>(_ command: C, timeout: TimeInterval) throws {
        guard let characteristic = peripheral.getCharacteristicWithUUID(.data) else {
            throw RileyLinkDeviceError.peripheralManagerError(PeripheralManagerError.unknownCharacteristic(MainServiceCharacteristicUUID.data.cbUUID))
        }

        let value = try command.writableData()

        log.debug("RL Send (no response expected): %@", value.hexadecimalString)

        do {
            try writeValue(value, for: characteristic, type: .withResponse, timeout: timeout)
        } catch let error as PeripheralManagerError {
            throw RileyLinkDeviceError.peripheralManagerError(error)
        }
    }
    
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    func readRadioFirmwareVersion(timeout: TimeInterval, responseType: ResponseType) throws -> String {
        let response = try writeCommand(GetVersion(), timeout: timeout, responseType: responseType)
        return response.version
    }

    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    func readBluetoothFirmwareVersion(timeout: TimeInterval) throws -> String {
        guard let characteristic = peripheral.getCharacteristicWithUUID(.firmwareVersion) else {
            throw RileyLinkDeviceError.peripheralManagerError(PeripheralManagerError.unknownCharacteristic(MainServiceCharacteristicUUID.firmwareVersion.cbUUID))
        }

        do {
            guard let data = try readValue(for: characteristic, timeout: timeout) else {
                throw RileyLinkDeviceError.peripheralManagerError(PeripheralManagerError.emptyValue)
            }

            guard let version = String(bytes: data, encoding: .utf8) else {
                throw RileyLinkDeviceError.invalidResponse(data)
            }

            return version
        } catch let error as PeripheralManagerError {
            throw RileyLinkDeviceError.peripheralManagerError(error)
        }
    }
}


// MARK: - Lower-level helper operations
extension PeripheralManager {
    
    func setOrangeNotifyOn() throws {
        perform { [self] (manager) in
            guard let characteristicNotif = peripheral.getOrangeCharacteristic(.orangeTX) else {
                return
            }
            
            do {
                try setNotifyValue(true, for: characteristicNotif, timeout: 2)
            } catch {
                log.error("setOrangeNotifyOn failed: %@", error.localizedDescription)
            }
        }
    }
    
    func orangeAction(_ command: OrangeLinkCommand) {
        if command != .off, command != .shakeOff {
            orangeWritePwd()
        }
        perform { [self] (manager) in
            do {
                guard let characteristic = peripheral.getOrangeCharacteristic(.orangeRX) else {
                    throw PeripheralManagerError.unknownCharacteristic(OrangeServiceCharacteristicUUID.orangeRX.cbUUID)
                }
                let value = Data([OrangeLinkRequestType.fctHeader.rawValue, command.rawValue])
                try writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (_) {
                log.debug("orangeAction failed")
            }
        }
        if command == .off, command == .shakeOff {
            orangeClose()
        }
    }
    
    func findDevice() {
        perform { [self] (manager) in
            do {
                guard let characteristic = peripheral.getOrangeCharacteristic(.orangeRX) else {
                    throw PeripheralManagerError.unknownCharacteristic(OrangeServiceCharacteristicUUID.orangeRX.cbUUID)
                }
                let value = Data([OrangeLinkRequestType.cfgHeader.rawValue, 0x04])
                try writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (_) {
                log.debug("findDevice failed")
            }
        }
    }
    
    func setOrangeConfig(_ config: OrangeLinkConfigurationSetting, isOn: Bool) {
        perform { [self] (manager) in
            do {
                guard let characteristic = peripheral.getOrangeCharacteristic(.orangeRX) else {
                    throw PeripheralManagerError.unknownCharacteristic(OrangeServiceCharacteristicUUID.orangeRX.cbUUID)
                }
                let value = Data([OrangeLinkRequestType.cfgHeader.rawValue, 0x02, config.rawValue, isOn ? 1 : 0])
                try writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (_) {
                log.debug("setOrangeConfig failed")
            }
        }
    }
    
    func orangeWritePwd() {
        perform { [self] (manager) in
            do {
                guard let characteristic = peripheral.getOrangeCharacteristic(.orangeRX) else {
                    throw PeripheralManagerError.unknownCharacteristic(OrangeServiceCharacteristicUUID.orangeRX.cbUUID)
                }
                let value = Data([0xAA])
                try writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (_) {
                log.debug("orangeWritePwd failed")
            }
        }
    }
    
    func orangeReadSet() {
        perform { [self] (manager) in
            do {
                guard let characteristic = peripheral.getOrangeCharacteristic(.orangeRX) else {
                    throw PeripheralManagerError.unknownCharacteristic(OrangeServiceCharacteristicUUID.orangeRX.cbUUID)
                }
                let value = Data([OrangeLinkRequestType.cfgHeader.rawValue, 0x01])
                log.debug("orangeReadSet write: %@", value.hexadecimalString)
                try writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (_) {
                log.debug("orangeReadSet failed")
            }
        }
    }
    
    func orangeReadVDC() {
        perform { [self] (manager) in
            do {
                guard let characteristic = peripheral.getOrangeCharacteristic(.orangeRX) else {
                    throw PeripheralManagerError.unknownCharacteristic(OrangeServiceCharacteristicUUID.orangeRX.cbUUID)
                }
                let value = Data([OrangeLinkRequestType.cfgHeader.rawValue, 0x03])
                try writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (_) {
                log.debug("orangeReadVDC failed")
            }
        }
    }
    
    func orangeClose() {
        perform { [self] (manager) in
            do {
                guard let characteristic = peripheral.getOrangeCharacteristic(.orangeRX) else {
                    throw PeripheralManagerError.unknownCharacteristic(OrangeServiceCharacteristicUUID.orangeRX.cbUUID)
                }
                let value = Data([0xcc])
                try writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (_) {
                log.debug("orangeClose failed")
            }
        }
    }
    
    /// Writes command data expecting a single response
    ///
    /// - Parameters:
    ///   - data: The command data
    ///   - characteristic: The peripheral characteristic to write
    ///   - type: The type of characteristic write
    ///   - timeout: The amount of time to wait for the peripheral to respond before throwing a timeout error
    /// - Returns: The recieved response
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    private func writeCommand<R: Response>(_ data: Data,
        for characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType = .withResponse,
        timeout: TimeInterval
    ) throws -> R
    {
        var capturedResponse: R?

        do {
            try runCommand(timeout: timeout) {
                if case .withResponse = type {
                    addCondition(.write(characteristic: characteristic))
                }

                addCondition(.valueUpdate(characteristic: characteristic, matching: { value in
                    guard let value = value, value.count > 0 else {
                        log.debug("Empty response from RileyLink. Continuing to listen for command response.")
                        return false
                    }
                    
                    log.debug("RL Recv(single): %@", value.hexadecimalString)

                    guard let code = ResponseCode(rawValue: value[0]) else {
                        let unknownCode = value[0..<1].hexadecimalString
                        log.error("Unknown response code from RileyLink: %{public}@. Continuing to listen for command response.", unknownCode)
                        return false
                    }

                    switch code {
                    case .commandInterrupted:
                        // This is expected in cases where an "Idle" GetPacket command is running
                        log.debug("Idle command interrupted. Continuing to listen for command response.")
                        return false
                    default:
                        guard let response = R(data: value) else {
                            log.error("Unable to parse response: %{public}@", value.hexadecimalString)
                            // We don't recognize the contents. Keep listening.
                            return false
                        }
                        log.debug("writeCommand response: %{public}@", String(describing: response))
                        capturedResponse = response
                        return true
                    }
                }))

                peripheral.writeValue(data, for: characteristic, type: type)
            }
        } catch let error as PeripheralManagerError {
            // If the write succeeded, but we get no response, BLE comms are working but RL command channel is hung
            if case .timeout(let unmetConditions) = error,
               let firstUnmetCondition = unmetConditions.first,
               case .valueUpdate = firstUnmetCondition
            {
                throw RileyLinkDeviceError.commandsBlocked
            } else {
                throw RileyLinkDeviceError.peripheralManagerError(error)
            }
        }

        guard let response = capturedResponse else {
            throw RileyLinkDeviceError.invalidResponse(characteristic.value ?? Data())
        }

        return response
    }

    /// Writes command data expecting a bufferred response
    ///
    /// - Parameters:
    ///   - data: The command data
    ///   - characteristic: The peripheral characteristic to write
    ///   - type: The type of characteristic write
    ///   - timeout: The amount of time to wait for the peripheral to respond before throwing a timeout error
    ///   - endOfResponseMarker: The marker delimiting the end of a response in the buffer
    /// - Returns: The received response. In the event of multiple responses in the buffer, the first parsable response is returned.
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    private func writeLegacyCommand<R: Response>(_ data: Data,
        for characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType = .withResponse,
        timeout: TimeInterval,
        endOfResponseMarker: UInt8
    ) throws -> R
    {
        var capturedResponse: R?
        var buffer = ResponseBuffer<R>(endMarker: endOfResponseMarker)

        do {
            try runCommand(timeout: timeout) {
                if case .withResponse = type {
                    addCondition(.write(characteristic: characteristic))
                }

                addCondition(.valueUpdate(characteristic: characteristic, matching: { value in
                    guard let value = value else {
                        return false
                    }

                    log.debug("RL Recv(buffered): %@", value.hexadecimalString)
                    buffer.append(value)

                    for response in buffer.responses {
                        switch response.code {
                        case .rxTimeout, .zeroData, .invalidParam, .unknownCommand:
                            log.debug("writeLegacyCommand response: %{public}@", String(describing: response))
                            capturedResponse = response
                            return true
                        case .commandInterrupted:
                            // This is expected in cases where an "Idle" GetPacket command is running
                            log.debug("writeLegacyCommand response (commandInterrupted): %{public}@", String(describing: response))
                        case .success:
                            capturedResponse = response
                            return true
                        }
                    }

                    return false
                }))

                peripheral.writeValue(data, for: characteristic, type: type)
            }
        } catch let error as PeripheralManagerError {
            throw RileyLinkDeviceError.peripheralManagerError(error)
        }

        guard let response = capturedResponse else {
            throw RileyLinkDeviceError.invalidResponse(characteristic.value ?? Data())
        }

        return response
    }
}
