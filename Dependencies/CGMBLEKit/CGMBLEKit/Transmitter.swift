//
//  Transmitter.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 11/22/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import CoreBluetooth
import HealthKit
import os.log


public protocol TransmitterDelegate: AnyObject {
    func transmitterDidConnect(_ transmitter: Transmitter)

    func transmitter(_ transmitter: Transmitter, didError error: Error)

    func transmitter(_ transmitter: Transmitter, didRead glucose: Glucose)

    func transmitter(_ transmitter: Transmitter, didReadBackfill glucose: [Glucose])

    func transmitter(_ transmitter: Transmitter, didReadUnknownData data: Data)
}

/// These methods are called on a private background queue. It is the responsibility of the client to ensure thread-safety.
public protocol TransmitterCommandSource: AnyObject {
    func dequeuePendingCommand(for transmitter: Transmitter) -> Command?

    func transmitter(_ transmitter: Transmitter, didFail command: Command, with error: Error)

    func transmitter(_ transmitter: Transmitter, didComplete command: Command)
}

public enum TransmitterError: Error {
    case authenticationError(String)
    case controlError(String)
    case observationError(String)
}

extension TransmitterError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .authenticationError(let description):
            return description
        case .controlError(let description):
            return description
        case .observationError(let description):
            return description
        }
    }
}


public final class Transmitter: BluetoothManagerDelegate {

    /// The ID of the transmitter to connect to
    public var ID: String {
        return id.id
    }

    private var id: TransmitterID

    public var passiveModeEnabled: Bool

    public weak var delegate: TransmitterDelegate?

    public weak var commandSource: TransmitterCommandSource?

    // MARK: - Passive observation state, confined to `bluetoothManager.managerQueue`

    /// The initial activation date of the transmitter
    private var activationDate: Date?

    /// The last-observed time message
    private var lastTimeMessage: TransmitterTimeRxMessage? {
        didSet {
            if let time = lastTimeMessage {
                activationDate = Date(timeIntervalSinceNow: -TimeInterval(time.currentTime))
            } else {
                activationDate = nil
            }
        }
    }

    /// The last-observed calibration message
    private var lastCalibrationMessage: CalibrationDataRxMessage?

    /// The backfill data buffer
    private var backfillBuffer: GlucoseBackfillFrameBuffer?

    // MARK: -

    private let log = OSLog(category: "Transmitter")

    private let bluetoothManager = BluetoothManager()

    private let delegateQueue = DispatchQueue(label: "com.loudnate.CGMBLEKit.delegateQueue", qos: .unspecified)

    public init(id: String, activationDate: Date?, peripheralIdentifier: UUID? = nil, passiveModeEnabled: Bool = false) {
        self.id = TransmitterID(id: id)
        self.passiveModeEnabled = passiveModeEnabled
        self.activationDate = activationDate

        bluetoothManager.peripheralIdentifier = peripheralIdentifier
        bluetoothManager.delegate = self
    }

    public func resumeScanning() {
        if stayConnected {
            bluetoothManager.scanForPeripheral()
        }
    }

    public func stopScanning() {
        bluetoothManager.disconnect()
    }

    public var isScanning: Bool {
        return bluetoothManager.isScanning
    }

    public var peripheralIdentifier: UUID? {
        get {
            return bluetoothManager.peripheralIdentifier
        }
        set {
            bluetoothManager.peripheralIdentifier = newValue
        }
    }

    public var stayConnected: Bool {
        get {
            return bluetoothManager.stayConnected
        }
        set {
            bluetoothManager.stayConnected = newValue

            if newValue {
                bluetoothManager.scanForPeripheral()
            }
        }
    }

    // MARK: - BluetoothManagerDelegate

    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, isReadyWithError error: Error?) {
        if let error = error {
            delegateQueue.async {
                self.delegate?.transmitter(self, didError: error)
            }
            return
        }

        delegateQueue.async {
            self.delegate?.transmitterDidConnect(self)
        }

        peripheralManager.perform { (peripheral) in
            if self.passiveModeEnabled {
                self.log.debug("Listening for authentication responses in passive mode")
                do {
                    try peripheral.listenToCharacteristic(.authentication)
                } catch let error {
                    self.delegateQueue.async {
                        self.delegate?.transmitter(self, didError: error)
                    }
                }
            } else {
                do {
                    self.log.debug("Authenticating with transmitter")
                    let status = try peripheral.authenticate(id: self.id)

                    if !status.isBonded {
                        self.log.debug("Requesting bond")
                        try peripheral.requestBond()

                        self.log.debug("Bonding request sent. Waiting user to respond.")
                    }

                    try peripheral.enableNotify(shouldWaitForBond: !status.isBonded)
                    defer {
                        self.log.debug("Initiating a disconnect")
                        peripheral.disconnect()
                    }

                    self.log.debug("Reading time")
                    let timeMessage = try peripheral.readTimeMessage()

                    let activationDate = Date(timeIntervalSinceNow: -TimeInterval(timeMessage.currentTime))
                    self.log.debug("Determined activation date: %@", String(describing: activationDate))

                    while let command = self.commandSource?.dequeuePendingCommand(for: self) {
                        self.log.debug("Sending command: %@", String(describing: command))
                        do {
                            _ = try peripheral.sendCommand(command, activationDate: activationDate)
                            self.commandSource?.transmitter(self, didComplete: command)
                        } catch let error {
                            self.commandSource?.transmitter(self, didFail: command, with: error)
                        }
                    }

                    self.log.debug("Reading glucose")
                    let glucoseMessage = try peripheral.readGlucose()
                    self.log.debug("Reading calibration data")
                    let calibrationMessage = try? peripheral.readCalibrationData()

                    let glucose = Glucose(
                        transmitterID: self.id.id,
                        glucoseMessage: glucoseMessage,
                        timeMessage: timeMessage,
                        calibrationMessage: calibrationMessage,
                        activationDate: activationDate
                    )

                    self.delegateQueue.async {
                        self.delegate?.transmitter(self, didRead: glucose)
                    }
                } catch let error {
                    self.delegateQueue.async {
                        self.delegate?.transmitter(self, didError: error)
                    }
                }
            }
        }
    }

    func bluetoothManager(_ manager: BluetoothManager, shouldConnectPeripheral peripheral: CBPeripheral) -> Bool {
        /// The Dexcom G5 advertises a peripheral name of "DexcomXX"
        /// where "XX" is the last-two characters of the transmitter ID.
        if let name = peripheral.name, name.suffix(2) == id.id.suffix(2) {
            return true
        } else {
            self.log.info("Not connecting to peripheral: %{public}@", peripheral.name ?? String(describing: peripheral))
            return false
        }
    }

    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, didReceiveControlResponse response: Data) {
        guard passiveModeEnabled else { return }

        guard response.count > 0 else { return }

        switch Opcode(rawValue: response[0]) {
        case .glucoseRx?, .glucoseG6Rx?:
            if  let glucoseMessage = GlucoseRxMessage(data: response),
                let timeMessage = lastTimeMessage,
                let activationDate = activationDate
            {
                delegateQueue.async {
                    self.delegate?.transmitter(self, didRead: Glucose(transmitterID: self.id.id, glucoseMessage: glucoseMessage, timeMessage: timeMessage, calibrationMessage: self.lastCalibrationMessage, activationDate: activationDate))
                }
            } else {
                delegateQueue.async {
                    self.delegate?.transmitter(self, didError: TransmitterError.observationError("Unable to handle glucose control response"))
                }
            }

            peripheralManager.perform { (peripheral) in
                // Subscribe to backfill updates
                do {
                    try peripheral.listenToCharacteristic(.backfill)
                } catch let error {
                    self.log.error("Error trying to enable notifications on backfill characteristic: %{public}@", String(describing: error))
                    self.delegateQueue.async {
                        self.delegate?.transmitter(self, didError: error)
                    }
                }
            }
        case .transmitterTimeRx?:
            if let timeMessage = TransmitterTimeRxMessage(data: response) {
                self.lastTimeMessage = timeMessage
            }
        case .glucoseBackfillRx?:
            guard let backfillMessage = GlucoseBackfillRxMessage(data: response) else {
                break
            }

            guard let backfillBuffer = backfillBuffer else {
                log.error("Received GlucoseBackfillRxMessage %{public}@ but backfillBuffer is nil", String(describing: backfillMessage))
                self.delegateQueue.async {
                    self.delegate?.transmitter(self, didError: TransmitterError.observationError("Received GlucoseBackfillRxMessage but backfillBuffer is nil"))
                }
                break
            }

            guard let timeMessage = lastTimeMessage, let activationDate = activationDate else {
                log.error("Received GlucoseBackfillRxMessage %{public}@ but activationDate is unknown", String(describing: backfillMessage))
                self.delegateQueue.async {
                    self.delegate?.transmitter(self, didError: TransmitterError.observationError("Received GlucoseBackfillRxMessage but activationDate is unknown"))
                }
                break
            }

            guard backfillMessage.bufferLength == backfillBuffer.count else {
                log.error("GlucoseBackfillRxMessage expected buffer length %d, but was %d", backfillMessage.bufferLength, backfillBuffer.count)
                self.delegateQueue.async {
                    self.delegate?.transmitter(self, didError: TransmitterError.observationError("GlucoseBackfillRxMessage expected buffer length \(backfillMessage.bufferLength), but was \(backfillBuffer.count): \(response.hexadecimalString) "))
                }
                break
            }

            guard backfillMessage.bufferCRC == backfillBuffer.crc16 else {
                log.error("GlucoseBackfillRxMessage expected CRC %04x, but was %04x", backfillMessage.bufferCRC, backfillBuffer.crc16)
                self.delegateQueue.async {
                    self.delegate?.transmitter(self, didError: TransmitterError.observationError("GlucoseBackfillRxMessage expected CRC \(backfillMessage.bufferCRC), but was \(backfillBuffer.crc16)"))
                }
                break
            }

            let glucose = backfillBuffer.glucose.map {
                Glucose(transmitterID: id.id, status: backfillMessage.status, glucoseMessage: $0, timeMessage: timeMessage, activationDate: activationDate)
            }

            guard glucose.count > 0 else {
                break
            }

            guard glucose.first!.glucoseMessage.timestamp == backfillMessage.startTime,
                glucose.last!.glucoseMessage.timestamp == backfillMessage.endTime,
                glucose.first!.glucoseMessage.timestamp <= glucose.last!.glucoseMessage.timestamp
            else {
                log.error("GlucoseBackfillRxMessage time interval not reflected in glucose: %{public}@, buffer: %{public}@", response.hexadecimalString, String(reflecting: backfillBuffer))

                self.delegateQueue.async {
                    self.delegate?.transmitter(self, didError: TransmitterError.observationError("GlucoseBackfillRxMessage time interval not reflected in glucose: \(backfillMessage.startTime) - \(backfillMessage.endTime), buffer: \(glucose.first!.glucoseMessage.timestamp) - \(glucose.last!.glucoseMessage.timestamp)"))
                }
                break
            }

            delegateQueue.async {
                self.delegate?.transmitter(self, didReadBackfill: glucose)
            }
        case .calibrationDataRx?:
            guard let calibrationDataMessage = CalibrationDataRxMessage(data: response) else {
                break
            }

            lastCalibrationMessage = calibrationDataMessage
        case .none:
            delegateQueue.async {
                self.delegate?.transmitter(self, didReadUnknownData: response)
            }
        default:
            // We ignore all other known opcodes
            break
        }
    }

    func bluetoothManager(_ manager: BluetoothManager, didReceiveBackfillResponse response: Data) {
        guard response.count > 2 else {
            return
        }

        if response[0] == 1 {
            log.info("Starting new backfill buffer with ID %d", response[1])

            self.backfillBuffer = GlucoseBackfillFrameBuffer(identifier: response[1])
        }
        
        log.info("appending to backfillBuffer: %@", response.hexadecimalString)

        self.backfillBuffer?.append(response)
    }

    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, didReceiveAuthenticationResponse response: Data) {

        if let message = AuthChallengeRxMessage(data: response), message.isBonded, message.isAuthenticated {
            self.log.debug("Observed authenticated session. enabling notifications for control characteristic.")
            peripheralManager.perform { (peripheral) in
                // Stopping updates from authentication simultaneously with Dexcom's app causes CoreBluetooth to get into a weird state.
                /*
                do {
                    try peripheral.stopListeningToCharacteristic(.authentication)
                } catch let error {
                    self.log.error("Error trying to disable notifications on authentication characteristic: %{public}@", String(describing: error))
                }
                */

                do {
                    try peripheral.listenToCharacteristic(.control)
                } catch let error {
                    self.log.error("Error trying to enable notifications on control characteristic: %{public}@", String(describing: error))
                    self.delegateQueue.async {
                        self.delegate?.transmitter(self, didError: error)
                    }
                }
            }
        } else {
            self.log.debug("Ignoring authentication response: %{public}@", response.hexadecimalString)
        }
    }
}

extension Transmitter: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## Transmitter",
            String(reflecting: bluetoothManager),
        ].joined(separator: "\n")
    }
}


struct TransmitterID {
    let id: String

    init(id: String) {
        self.id = id
    }

    private var cryptKey: Data? {
        return "00\(id)00\(id)".data(using: .utf8)
    }

    func computeHash(of data: Data) -> Data? {
        guard data.count == 8, let key = cryptKey else {
            return nil
        }

        var doubleData = Data(capacity: data.count * 2)
        doubleData.append(data)
        doubleData.append(data)

        guard let outData = try? AESCrypt.encryptData(doubleData, usingKey: key) else {
            return nil
        }

        return outData[0..<8]
    }
}


// MARK: - Helpers
fileprivate extension PeripheralManager {
    func authenticate(id: TransmitterID) throws -> AuthChallengeRxMessage {
        let authMessage = AuthRequestTxMessage()

        do {
            try writeMessage(authMessage, for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Error writing transmitter challenge: \(error)")
        }

        let authResponse: AuthRequestRxMessage
        do {
            authResponse = try readMessage(for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Unable to parse auth challenge: \(error)")
        }

        guard authResponse.tokenHash == id.computeHash(of: authMessage.singleUseToken) else {
            throw TransmitterError.authenticationError("Transmitter failed auth challenge")
        }

        guard let challengeHash = id.computeHash(of: authResponse.challenge) else {
            throw TransmitterError.authenticationError("Failed to compute challenge hash for transmitter ID")
        }

        do {
            try writeMessage(AuthChallengeTxMessage(challengeHash: challengeHash), for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Error writing challenge response: \(error)")
        }

        let challengeResponse: AuthChallengeRxMessage
        do {
            challengeResponse = try readMessage(for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Unable to parse auth status: \(error)")
        }

        guard challengeResponse.isAuthenticated else {
            throw TransmitterError.authenticationError("Transmitter rejected auth challenge")
        }

        return challengeResponse
    }

    func requestBond() throws {
        do {
            try writeMessage(KeepAliveTxMessage(time: 25), for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Error writing keep-alive for bond: \(error)")
        }

        do {
            try writeMessage(BondRequestTxMessage(), for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Error writing bond request: \(error)")
        }
    }

    func enableNotify(shouldWaitForBond: Bool = false) throws {
        do {
            if shouldWaitForBond {
                try setNotifyValue(true, for: .control, timeout: 15)
            } else {
                try setNotifyValue(true, for: .control)
            }
        } catch let error {
            throw TransmitterError.controlError("Error enabling notification: \(error)")
        }
    }

    func readTimeMessage() throws -> TransmitterTimeRxMessage {
        do {
            return try writeMessage(TransmitterTimeTxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting time: \(error)")
        }
    }

    /// - Throws: TransmitterError.controlError
    func sendCommand(_ command: Command, activationDate: Date) throws -> TransmitterRxMessage {
        do {
            switch command {
            case .startSensor(let date):
                let startTime = UInt32(date.timeIntervalSince(activationDate))
                let secondsSince1970 = UInt32(date.timeIntervalSince1970)
                return try writeMessage(SessionStartTxMessage(startTime: startTime, secondsSince1970: secondsSince1970), for: .control)
            case .stopSensor(let date):
                let stopTime = UInt32(date.timeIntervalSince(activationDate))
                return try writeMessage(SessionStopTxMessage(stopTime: stopTime), for: .control)
            case .calibrateSensor(let glucose, let date):
                let glucoseValue = UInt16(glucose.doubleValue(for: .milligramsPerDeciliter).rounded())
                let time = UInt32(date.timeIntervalSince(activationDate))
                return try writeMessage(CalibrateGlucoseTxMessage(time: time, glucose: glucoseValue), for: .control)
            case .resetTransmitter:
                return try writeMessage(ResetTxMessage(), for: .control)
            }
        } catch let error {
            throw TransmitterError.controlError("Error during \(command): \(error)")
        }
    }

    func readGlucose() throws -> GlucoseRxMessage {
        do {
            return try writeMessage(GlucoseTxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting glucose: \(error)")
        }
    }

    func readCalibrationData() throws -> CalibrationDataRxMessage {
        do {
            return try writeMessage(CalibrationDataTxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting calibration data: \(error)")
        }
    }

    func disconnect() {
        do {
            try setNotifyValue(false, for: .control)
            try writeMessage(DisconnectTxMessage(), for: .control)
        } catch {
        }
    }

    func listenToCharacteristic(_ characteristic: CGMServiceCharacteristicUUID) throws {
        do {
            try setNotifyValue(true, for: characteristic)
        } catch let error {
            throw TransmitterError.controlError("Error enabling notification for \(characteristic): \(error)")
        }
    }

    func stopListeningToCharacteristic(_ characteristic: CGMServiceCharacteristicUUID) throws {
        do {
            try setNotifyValue(false, for: characteristic)
        } catch let error {
            throw TransmitterError.controlError("Error disabling notification for \(characteristic): \(error)")
        }
    }
}
