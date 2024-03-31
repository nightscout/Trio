//
//  G7Sensor.swift
//  CGMBLEKit
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreBluetooth
import HealthKit
import os.log


public protocol G7SensorDelegate: AnyObject {
    func sensorDidConnect(_ sensor: G7Sensor, name: String)

    func sensorDisconnected(_ sensor: G7Sensor, suspectedEndOfSession: Bool)

    func sensor(_ sensor: G7Sensor, didError error: Error)

    func sensor(_ sensor: G7Sensor, didRead glucose: G7GlucoseMessage)

    func sensor(_ sensor: G7Sensor, didReadBackfill backfill: [G7BackfillMessage])

    // If this returns true, then start following this sensor
    func sensor(_ sensor: G7Sensor, didDiscoverNewSensor name: String, activatedAt: Date) -> Bool

    // This is triggered for connection/disconnection events, and enabling/disabling scan
    func sensorConnectionStatusDidUpdate(_ sensor: G7Sensor)
}

public enum G7SensorError: Error {
    case authenticationError(String)
    case controlError(String)
    case observationError(String)
}

extension G7SensorError: CustomStringConvertible {
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

public enum G7SensorLifecycleState {
    case searching
    case warmup
    case ok
    case failed
    case gracePeriod
    case expired
}


public final class G7Sensor: G7BluetoothManagerDelegate {
    public static let lifetime = TimeInterval(hours: 10 * 24)
    public static let warmupDuration = TimeInterval(minutes: 25)
    public static let gracePeriod = TimeInterval(hours: 12)

    public weak var delegate: G7SensorDelegate?

    // MARK: - Passive observation state, confined to `bluetoothManager.managerQueue`

    /// The initial activation date of the sensor
    var activationDate: Date?

    /// The date of last connection
    private var lastConnection: Date?

    /// Used to detect connections that do not authenticate, signalling possible sensor switchover
    private var pendingAuth: Bool = false

    /// The backfill data buffer
    private var backfillBuffer: [G7BackfillMessage] = []

    // MARK: -

    private let log = OSLog(category: "G7Sensor")

    private let bluetoothManager = G7BluetoothManager()

    private let delegateQueue = DispatchQueue(label: "com.loopkit.G7Sensor.delegateQueue", qos: .unspecified)

    private var sensorID: String?

    public func setSensorId(_ newId: String) {
        self.sensorID = newId
    }

    public init(sensorID: String?) {
        self.sensorID = sensorID
        bluetoothManager.delegate = self
    }

    public func scanForNewSensor() {
        self.sensorID = nil
        bluetoothManager.disconnect()
        bluetoothManager.forgetPeripheral()
        bluetoothManager.scanForPeripheral()
    }

    public func resumeScanning() {
        bluetoothManager.scanForPeripheral()
    }

    public func stopScanning() {
        bluetoothManager.disconnect()
    }

    public var isScanning: Bool {
        return bluetoothManager.isScanning
    }

    public var isConnected: Bool {
        return bluetoothManager.isConnected
    }

    private func handleGlucoseMessage(message: G7GlucoseMessage, peripheralManager: G7PeripheralManager) {
        activationDate = Date().addingTimeInterval(-TimeInterval(message.glucoseTimestamp))
        peripheralManager.perform { (peripheral) in
            self.log.debug("Listening for backfill responses")
            // Subscribe to backfill updates
            do {
                try peripheral.listenToCharacteristic(.backfill)
            } catch let error {
                self.log.error("Error trying to enable notifications on backfill characteristic: %{public}@", String(describing: error))
                self.delegateQueue.async {
                    self.delegate?.sensor(self, didError: error)
                }
            }
        }
        if sensorID == nil, let name = peripheralManager.peripheral.name, let activationDate = activationDate  {
            delegateQueue.async {
                guard let delegate = self.delegate else {
                    return
                }

                if delegate.sensor(self, didDiscoverNewSensor: name, activatedAt: activationDate) {
                    self.sensorID = name
                    self.activationDate = activationDate
                    self.delegate?.sensor(self, didRead: message)
                    self.bluetoothManager.stopScanning()
                }
            }
        } else if sensorID != nil {
            delegateQueue.async {
                self.delegate?.sensor(self, didRead: message)
            }
        } else {
            self.log.error("Dropping unhandled glucose message: %{public}@", String(describing: message))
        }
    }

    // MARK: - BluetoothManagerDelegate

    func bluetoothManager(_ manager: G7BluetoothManager, readied peripheralManager: G7PeripheralManager) -> Bool {
        var shouldStopScanning = false;

        if let sensorID = sensorID, sensorID == peripheralManager.peripheral.name {
            shouldStopScanning = true
            delegateQueue.async {
                self.delegate?.sensorDidConnect(self, name: sensorID)
            }
        }

        peripheralManager.perform { (peripheral) in
            self.log.info("Listening for authentication responses for %{public}@", String(describing: peripheralManager.peripheral.name))
            do {
                try peripheral.listenToCharacteristic(.authentication)
                self.pendingAuth = true
            } catch let error {
                self.delegateQueue.async {
                    self.delegate?.sensor(self, didError: error)
                }
            }
        }
        return shouldStopScanning
    }

    func bluetoothManager(_ manager: G7BluetoothManager, readyingFailed peripheralManager: G7PeripheralManager, with error: Error) {
        delegateQueue.async {
            self.delegate?.sensor(self, didError: error)
        }
    }

    func peripheralDidDisconnect(_ manager: G7BluetoothManager, peripheralManager: G7PeripheralManager, wasRemoteDisconnect: Bool) {
        if let sensorID = sensorID, sensorID == peripheralManager.peripheral.name {

            let suspectedEndOfSession: Bool
            if pendingAuth && wasRemoteDisconnect {
                suspectedEndOfSession = true // Normal disconnect without auth is likely that G7 app stopped this session
            } else {
                suspectedEndOfSession = false
            }
            pendingAuth = false

            delegateQueue.async {
                self.delegate?.sensorDisconnected(self, suspectedEndOfSession: suspectedEndOfSession)
            }
        }
    }

    func bluetoothManager(_ manager: G7BluetoothManager, shouldConnectPeripheral peripheral: CBPeripheral) -> PeripheralConnectionCommand {

        guard let name = peripheral.name else {
            log.debug("Not connecting to unnamed peripheral: %{public}@", String(describing: peripheral))
            return .ignore
        }

        /// The Dexcom G7 advertises a peripheral name of "DXCMxx", and later reports a full name of "Dexcomxx"
        /// Dexcom One+ peripheral name start with "DX02"
        if name.hasPrefix("DXCM") || name.hasPrefix("DX02"){
            // If we're following this name or if we're scanning, connect
            if let sensorName = sensorID, name.suffix(2) == sensorName.suffix(2) {
                return .makeActive
            } else if sensorID == nil {
                return .connect
            }
        }

        log.info("Not connecting to peripheral: %{public}@", name)
        return .ignore
    }

    func bluetoothManager(_ manager: G7BluetoothManager, peripheralManager: G7PeripheralManager, didReceiveControlResponse response: Data) {

        guard response.count > 0 else { return }

        log.debug("Received control response: %{public}@", response.hexadecimalString)

        switch G7Opcode(rawValue: response[0]) {
        case .glucoseTx?:
            if let glucoseMessage = G7GlucoseMessage(data: response) {
                handleGlucoseMessage(message: glucoseMessage, peripheralManager: peripheralManager)
            } else {
                delegateQueue.async {
                    self.delegate?.sensor(self, didError: G7SensorError.observationError("Unable to handle glucose control response"))
                }
            }
        case .backfillFinished:
            if backfillBuffer.count > 0 {
                delegateQueue.async {
                    self.delegate?.sensor(self, didReadBackfill: self.backfillBuffer)
                    self.backfillBuffer = []
                }
            }
        default:
            // We ignore all other known opcodes
            break
        }
    }

    func bluetoothManager(_ manager: G7BluetoothManager, didReceiveBackfillResponse response: Data) {

        log.debug("Received backfill response: %{public}@", response.hexadecimalString)

        guard response.count == 9 else {
            return
        }

        if let msg = G7BackfillMessage(data: response) {
            backfillBuffer.append(msg)
        }
    }

    func bluetoothManager(_ manager: G7BluetoothManager, peripheralManager: G7PeripheralManager, didReceiveAuthenticationResponse response: Data) {

        if let message = AuthChallengeRxMessage(data: response), message.isBonded, message.isAuthenticated {
            log.debug("Observed authenticated session. enabling notifications for control characteristic.")
            pendingAuth = false
            peripheralManager.perform { (peripheral) in
                do {
                    try peripheral.listenToCharacteristic(.control)
                } catch let error {
                    self.log.error("Error trying to enable notifications on control characteristic: %{public}@", String(describing: error))
                    self.delegateQueue.async {
                        self.delegate?.sensor(self, didError: error)
                    }
                }
            }
        } else {
            log.debug("Ignoring authentication response: %{public}@", response.hexadecimalString)
        }
    }

    func bluetoothManagerScanningStatusDidChange(_ manager: G7BluetoothManager) {
        self.delegateQueue.async {
            self.delegate?.sensorConnectionStatusDidUpdate(self)
        }
    }
}


// MARK: - Helpers
fileprivate extension G7PeripheralManager {

    func listenToCharacteristic(_ characteristic: CGMServiceCharacteristicUUID) throws {
        do {
            try setNotifyValue(true, for: characteristic)
        } catch let error {
            throw G7SensorError.controlError("Error enabling notification for \(characteristic): \(error)")
        }
    }
}
