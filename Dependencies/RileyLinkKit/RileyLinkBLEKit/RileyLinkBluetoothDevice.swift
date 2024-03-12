//
//  RileyLinkBluetoothDevice.swift
//  RileyLinkBLEKit
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import CoreBluetooth
import os.log

public class RileyLinkBluetoothDevice: RileyLinkDevice {
    private let manager: PeripheralManager

    private let log = OSLog(category: "RileyLinkDevice")

    // Confined to `manager.queue`
    private var bleFirmwareVersion: BLEFirmwareVersion?

    // Confined to `manager.queue`
    private var radioFirmwareVersion: RadioFirmwareVersion?

    public var isConnected: Bool {
        return manager.peripheral.state == .connected
    }

    func setPeripheral(_ peripheral: CBPeripheral) {
        manager.peripheral = peripheral
    }

    public var rlFirmwareDescription: String {
        let versions = [radioFirmwareVersion, bleFirmwareVersion].compactMap { (version: CustomStringConvertible?) -> String? in
            if let version = version {
                return String(describing: version)
            } else {
                return nil
            }
        }

        return versions.joined(separator: " / ")
    }

    private var version: String {
        switch hardwareType {
        case .riley, .ema, .none:
            return rlFirmwareDescription
        case .orange:
            return orangeLinkFirmwareHardwareVersion
        }
    }

    // Confined to `lock`
    private var idleListeningState: IdleListeningState = .disabled

    // Confined to `lock`
    private var lastIdle: Date?

    // Confined to `lock`
    // TODO: Tidy up this state/preference machine
    private var isIdleListeningPending = false

    // Confined to `lock`
    private var isTimerTickEnabled = true

    /// Serializes access to device state
    private var lock = os_unfair_lock()

    private var orangeLinkFirmwareHardwareVersion = "v1.x"
    private var orangeLinkHardwareVersionMajorMinor: [Int]?
    private var ledOn: Bool = false
    private var vibrationOn: Bool = false
    private var voltage: Float?
    private var batteryLevel: Int?
    private var hasPiezo: Bool {
        if let olHW = orangeLinkHardwareVersionMajorMinor, olHW[0] == 1, olHW[1] >= 1 {
            return true
        } else if let olHW = orangeLinkHardwareVersionMajorMinor, olHW[0] == 2, olHW[1] == 6 {
            return true
       }
        return false
    }

    public var hasOrangeLinkService: Bool {
        return self.manager.peripheral.services?.itemWithUUID(RileyLinkServiceUUID.orange.cbUUID) != nil
    }

    public var hardwareType: RileyLinkHardwareType? {
        guard let services = self.manager.peripheral.services else {
            return nil
        }

        guard let bleComponents = self.bleFirmwareVersion else {
            return nil
        }

        if services.itemWithUUID(RileyLinkServiceUUID.secureDFU.cbUUID) != nil {
            return .orange
        } else if bleComponents.components[0] == 3 {
            // this returns true for riley with ema firmware, but that is OK
            return .ema
        } else {
            // as long as riley ble remains at 2.x with ema at 3.x this will work
            return .riley
        }
      }

    /// The queue used to serialize sessions and observe when they've drained
    private let sessionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.rileylink.RileyLinkBLEKit.RileyLinkDevice.sessionQueue"
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    private var sessionQueueOperationCountObserver: NSKeyValueObservation!

    public var rssi: Int?

    init(peripheralManager: PeripheralManager, rssi: Int?) {
        self.manager = peripheralManager
        self.rssi = rssi
        sessionQueue.underlyingQueue = peripheralManager.queue

        peripheralManager.delegate = self

        sessionQueueOperationCountObserver = sessionQueue.observe(\.operationCount, options: [.new]) { [weak self] (queue, change) in
            if let newValue = change.newValue, newValue == 0 {
                self?.log.debug("Session queue operation count is now empty")
                self?.assertIdleListening(forceRestart: true)
            }
        }
    }
}


// MARK: - Peripheral operations. Thread-safe.
extension RileyLinkBluetoothDevice {
    public var name: String? {
        return manager.peripheral.name
    }

    public var deviceURI: String {
        return "rileylink://\(name ?? peripheralIdentifier.uuidString)"
    }

    public var peripheralIdentifier: UUID {
        return manager.peripheral.identifier
    }

    public var peripheralState: CBPeripheralState {
        return manager.peripheral.state
    }

    public func readRSSI() {
        guard case .connected = manager.peripheral.state, case .poweredOn? = manager.central?.state else {
            return
        }
        manager.peripheral.readRSSI()
    }

    public func setCustomName(_ name: String) {
        manager.setCustomName(name)
    }

    public func updateBatteryLevel() {
        manager.readBatteryLevel { value in
            if let batteryLevel = value {
                self.batteryLevel = batteryLevel
                NotificationCenter.default.post(
                    name: .DeviceBatteryLevelUpdated,
                    object: self,
                    userInfo: [RileyLinkBluetoothDevice.batteryLevelKey: batteryLevel]
                )
                NotificationCenter.default.post(name: .DeviceStatusUpdated, object: self)
            }
        }
    }

    public func orangeAction(_ command: OrangeLinkCommand) {
        log.debug("orangeAction: %@", "\(command)")
        manager.orangeAction(command)
    }

    public func setOrangeConfig(_ config: OrangeLinkConfigurationSetting, isOn: Bool) {
        log.debug("setOrangeConfig: %@, %@", "\(String(describing: config))", "\(isOn)")
        manager.setOrangeConfig(config, isOn: isOn)
    }

    public func orangeWritePwd() {
        log.debug("orangeWritePwd")
        manager.orangeWritePwd()
    }

    public func orangeClose() {
        log.debug("orangeClose")
        manager.orangeClose()
    }

    public func orangeReadSet() {
        log.debug("orangeReadSet")
        manager.orangeReadSet()
    }

    public func orangeReadVDC() {
        log.debug("orangeReadVDC")
        manager.orangeReadVDC()
    }

    public func findDevice() {
        log.debug("findDevice")
        manager.findDevice()
    }

    public func setDiagnosticeLEDModeForBLEChip(_ mode: RileyLinkLEDMode) {
        manager.setLEDMode(mode: mode)
    }

    public func readDiagnosticLEDModeForBLEChip(completion: @escaping (RileyLinkLEDMode?) -> Void) {
        manager.readDiagnosticLEDMode(completion: completion)
    }

    /// Asserts that the caller is currently on the session queue
    public func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(manager.queue))
    }

    /// Schedules a closure to execute on the session queue after a specified time
    ///
    /// - Parameters:
    ///   - deadline: The time after which to execute
    ///   - execute: The closure to execute
    public func sessionQueueAsyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) {
        manager.queue.asyncAfter(deadline: deadline, execute: execute)
    }
}


extension RileyLinkBluetoothDevice: Equatable, Hashable {
    public static func ==(lhs: RileyLinkBluetoothDevice, rhs: RileyLinkBluetoothDevice) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(peripheralIdentifier)
    }
}


// MARK: - Status management
extension RileyLinkBluetoothDevice {

    public func getStatus(_ completion: @escaping (_ status: RileyLinkDeviceStatus) -> Void) {
        os_unfair_lock_lock(&lock)
        let lastIdle = self.lastIdle
        os_unfair_lock_unlock(&lock)

        self.manager.queue.async {
            completion(RileyLinkDeviceStatus(
                lastIdle: lastIdle,
                name: self.name,
                version: self.version,
                ledOn: self.ledOn,
                vibrationOn: self.vibrationOn,
                voltage: self.voltage,
                battery: self.batteryLevel,
                hasPiezo: self.hasPiezo
            ))
        }
    }
}


// MARK: - Command session management
// CommandSessions are a way to serialize access to the RileyLink command/response facility.
// All commands that send data out on the RL data characteristic need to be in a command session.
// Accessing other characteristics on the RileyLink can be done without a command session.
extension RileyLinkBluetoothDevice {
    public func runSession(withName name: String, _ block: @escaping (_ session: CommandSession) -> Void) {
        self.log.default("Scheduling session %{public}@", name)
        sessionQueue.addOperation(manager.configureAndRun({ [weak self] (manager) in
            self?.log.default("======================== %{public}@ ===========================", name)
            let bleFirmwareVersion = self?.bleFirmwareVersion
            let radioFirmwareVersion = self?.radioFirmwareVersion

            if bleFirmwareVersion == nil || radioFirmwareVersion == nil {
                self?.log.error("Running session with incomplete configuration: bleFirmwareVersion %{public}@, radioFirmwareVersion: %{public}@", String(describing: bleFirmwareVersion), String(describing: radioFirmwareVersion))
            }

            block(CommandSession(manager: manager, responseType: bleFirmwareVersion?.responseType ?? .buffered, firmwareVersion: radioFirmwareVersion ?? .unknown))
            self?.log.default("------------------------ %{public}@ ---------------------------", name)
        }))
    }
}


// MARK: - Idle management
extension RileyLinkBluetoothDevice {
    public enum IdleListeningState {
        case enabled(timeout: TimeInterval, channel: UInt8)
        case disabled
    }

    func setIdleListeningState(_ state: IdleListeningState) {
        os_unfair_lock_lock(&lock)
        let oldValue = idleListeningState
        idleListeningState = state
        os_unfair_lock_unlock(&lock)

        switch (oldValue, state) {
        case (.disabled, .enabled):
            assertIdleListening(forceRestart: true)
        case (.enabled, .enabled):
            assertIdleListening(forceRestart: false)
        default:
            break
        }
    }

    public func assertIdleListening(forceRestart: Bool = false) {
        os_unfair_lock_lock(&lock)
        guard case .enabled(timeout: let timeout, channel: let channel) = self.idleListeningState else {
            os_unfair_lock_unlock(&lock)
            return
        }

        guard case .connected = self.manager.peripheral.state, case .poweredOn? = self.manager.central?.state else {
            os_unfair_lock_unlock(&lock)
            return
        }

        guard forceRestart || (self.lastIdle ?? .distantPast).timeIntervalSinceNow < -timeout else {
            os_unfair_lock_unlock(&lock)
            return
        }

        guard !self.isIdleListeningPending else {
            os_unfair_lock_unlock(&lock)
            return
        }

        self.isIdleListeningPending = true
        os_unfair_lock_unlock(&lock)

        self.manager.startIdleListening(idleTimeout: timeout, channel: channel) { (error) in
            os_unfair_lock_lock(&self.lock)
            self.isIdleListeningPending = false

            if let error = error {
                self.log.error("Unable to start idle listening: %@", String(describing: error))
                os_unfair_lock_unlock(&self.lock)
            } else {
                self.lastIdle = Date()
                self.log.debug("Started idle listening")
                os_unfair_lock_unlock(&self.lock)
                NotificationCenter.default.post(name: .DeviceDidStartIdle, object: self)
            }
        }
    }
}


// MARK: - Timer tick management
extension RileyLinkBluetoothDevice {
    func setTimerTickEnabled(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        self.isTimerTickEnabled = enabled
        os_unfair_lock_unlock(&lock)
        self.assertTimerTick()
    }

    func assertTimerTick() {
        os_unfair_lock_lock(&self.lock)
        let isTimerTickEnabled = self.isTimerTickEnabled
        os_unfair_lock_unlock(&self.lock)

        if isTimerTickEnabled != self.manager.timerTickEnabled {
            self.manager.setTimerTickEnabled(isTimerTickEnabled)
        }
    }
}


// MARK: - CBCentralManagerDelegate Proxying
extension RileyLinkBluetoothDevice {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if case .poweredOn = central.state {
            assertIdleListening(forceRestart: false)
            assertTimerTick()
        }

        manager.centralManagerDidUpdateState(central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.default("didConnect %{public}@", peripheral)
        if case .connected = peripheral.state {
            assertIdleListening(forceRestart: false)
            assertTimerTick()
        }

        manager.centralManager(central, didConnect: peripheral)
        NotificationCenter.default.post(name: .DeviceConnectionStateDidChange, object: self)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.default("didDisconnectPeripheral %{public}@", peripheral)
        NotificationCenter.default.post(name: .DeviceConnectionStateDidChange, object: self)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.default("didFailToConnect %{public}@", peripheral)
        NotificationCenter.default.post(name: .DeviceConnectionStateDidChange, object: self)
    }
}


extension RileyLinkBluetoothDevice: PeripheralManagerDelegate {
    func peripheralManager(_ manager: PeripheralManager, didUpdateNotificationStateFor characteristic: CBCharacteristic) {
        log.debug("Did didUpdateNotificationStateFor %@", characteristic)
    }

    // If PeripheralManager receives a response on the data queue, without an outstanding request,
    // it will pass the update to this method, which is called on the central's queue.
    // This is how idle listen responses are handled
    func peripheralManager(_ manager: PeripheralManager, didUpdateValueFor characteristic: CBCharacteristic) {
        let characteristicService: CBService? = characteristic.service
        guard let cbService = characteristicService, let service = RileyLinkServiceUUID(rawValue: cbService.uuid.uuidString) else {
            log.debug("Update from characteristic on unknown service: %@", String(describing: characteristic.service))
            return
        }

        switch service {
        case .main:
            guard let mainCharacteristic = MainServiceCharacteristicUUID(rawValue: characteristic.uuid.uuidString) else {
                log.debug("Update from unknown characteristic %@ on main service.", characteristic.uuid.uuidString)
                return
            }
            handleCharacteristicUpdate(mainCharacteristic, value: characteristic.value)

        case .orange:
            guard let orangeCharacteristic = OrangeServiceCharacteristicUUID(rawValue: characteristic.uuid.uuidString) else {
                log.debug("Update from unknown characteristic %@ on orange service.", characteristic.uuid.uuidString)
                return
            }
            handleCharacteristicUpdate(orangeCharacteristic, value: characteristic.value)
        default:
            return
        }
    }

    private func handleCharacteristicUpdate(_ characteristic: MainServiceCharacteristicUUID, value: Data?) {
        switch characteristic {
        case .data:
            guard let value = value, value.count > 0 else {
                return
            }

            self.manager.queue.async {
                if let responseType = self.bleFirmwareVersion?.responseType {
                    let response: PacketResponse?

                    switch responseType {
                    case .buffered:
                        var buffer =  ResponseBuffer<PacketResponse>(endMarker: 0x00)
                        buffer.append(value)
                        response = buffer.responses.last
                    case .single:
                        response = PacketResponse(data: value)
                    }

                    if let response = response {
                        switch response.code {
                        case .commandInterrupted:
                            self.log.debug("Received commandInterrupted during idle; assuming device is still listening.")
                            return
                        case .rxTimeout, .zeroData, .invalidParam, .unknownCommand:
                            self.log.debug("Idle error received: %@", String(describing: response.code))
                        case .success:
                            if let packet = response.packet {
                                self.log.default("Idle packet received: %{public}@", String(describing: packet))
                                NotificationCenter.default.post(
                                    name: .DevicePacketReceived,
                                    object: self,
                                    userInfo: [RileyLinkBluetoothDevice.notificationPacketKey: packet]
                                )
                            }
                        }
                    } else {
                        self.log.error("Unknown idle response: %{public}@", value.hexadecimalString)
                    }
                } else {
                    self.log.error("Skipping parsing characteristic value update due to missing BLE firmware version")
                }
                self.assertIdleListening(forceRestart: true)
            }
        case .responseCount:
            // PeripheralManager.Configuration.valueUpdateMacros is responsible for handling this response.
            break
        case .timerTick:
            NotificationCenter.default.post(name: .DeviceTimerDidTick, object: self)
            assertIdleListening(forceRestart: false)
        case .customName, .firmwareVersion, .ledMode:
            break
        }
    }

    private func handleCharacteristicUpdate(_ characteristic: OrangeServiceCharacteristicUUID, value: Data?) {
        switch characteristic {
        case .orangeRX, .orangeTX:
            guard let data = value, !data.isEmpty else { return }
            if data.first == 0xbb {
                guard data.count > 6 else { return }
                if data[1] == 0x09, data[2] == 0xaa {
                    orangeLinkFirmwareHardwareVersion = "FW\(data[3]).\(data[4])/HW\(data[5]).\(data[6])"
                    orangeLinkHardwareVersionMajorMinor = [Int(data[5]), Int(data[6])]
                    NotificationCenter.default.post(name: .DeviceStatusUpdated, object: self)
                }
            } else if data.first == OrangeLinkRequestType.cfgHeader.rawValue {
                guard data.count > 2 else { return }
                if data[1] == 0x01 {
                    guard data.count > 5 else { return }
                    ledOn = (data[3] != 0)
                    vibrationOn = (data[4] != 0)
                    NotificationCenter.default.post(name: .DeviceStatusUpdated, object: self)
                } else if data[1] == 0x03 {
                    guard data.count > 4 else { return }
                    let int = UInt16(bigEndian: Data(data[3...4]).withUnsafeBytes { $0.load(as: UInt16.self) })
                    voltage = Float(int) / 1000
                    NotificationCenter.default.post(name: .DeviceStatusUpdated, object: self)
                }
            }
        }
    }

    func peripheralManager(_ manager: PeripheralManager, didReadRSSI RSSI: NSNumber, error: Error?) {
        self.rssi = Int(truncating: RSSI)
        NotificationCenter.default.post(
            name: .DeviceRSSIDidChange,
            object: self,
            userInfo: [RileyLinkBluetoothDevice.notificationRSSIKey: RSSI]
        )
    }

    func peripheralManagerDidUpdateName(_ manager: PeripheralManager) {
        NotificationCenter.default.post(
            name: .DeviceNameDidChange,
            object: self,
            userInfo: nil
        )
    }

    func completeConfiguration(for manager: PeripheralManager) throws {
        // Read bluetooth version to determine compatibility
        log.default("Reading firmware versions for PeripheralManager configuration")
        let bleVersionString = try manager.readBluetoothFirmwareVersion(timeout: 1)
        bleFirmwareVersion = BLEFirmwareVersion(versionString: bleVersionString)

        let radioVersionString = try manager.readRadioFirmwareVersion(timeout: 1, responseType: bleFirmwareVersion?.responseType ?? .buffered)
        radioFirmwareVersion = RadioFirmwareVersion(versionString: radioVersionString)

        try manager.setOrangeNotifyOn()
    }
}


extension RileyLinkBluetoothDevice: CustomDebugStringConvertible {

    public var debugDescription: String {
        os_unfair_lock_lock(&lock)
        let lastIdle = self.lastIdle
        let isIdleListeningPending = self.isIdleListeningPending
        let isTimerTickEnabled = self.isTimerTickEnabled
        os_unfair_lock_unlock(&lock)

        return [
            "## RileyLinkDevice",
            "* name: \(name ?? "")",
            "* lastIdle: \(lastIdle ?? .distantPast)",
            "* isIdleListeningPending: \(isIdleListeningPending)",
            "* isTimerTickEnabled: \(isTimerTickEnabled)",
            "* isTimerTickNotifying: \(manager.timerTickEnabled)",
            "* radioFirmware: \(String(describing: radioFirmwareVersion))",
            "* bleFirmware: \(String(describing: bleFirmwareVersion))",
            "* peripheralManager: \(manager)",
            "* sessionQueue.operationCount: \(sessionQueue.operationCount)"
        ].joined(separator: "\n")
    }
}

extension RileyLinkBluetoothDevice {
    public static let notificationPacketKey = "com.rileylink.RileyLinkBLEKit.RileyLinkDevice.NotificationPacket"

    public static let notificationRSSIKey = "com.rileylink.RileyLinkBLEKit.RileyLinkDevice.NotificationRSSI"

    public static let batteryLevelKey = "com.rileylink.RileyLinkBLEKit.RileyLinkDevice.BatteryLevel"
}


extension Notification.Name {
    public static let DeviceConnectionStateDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.ConnectionStateDidChange")

    public static let DeviceDidStartIdle = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.DidStartIdle")

    public static let DeviceNameDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.NameDidChange")

    public static let DevicePacketReceived = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.PacketReceived")

    public static let DeviceRSSIDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.RSSIDidChange")

    public static let DeviceTimerDidTick = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.TimerTickDidChange")

    public static let DeviceStatusUpdated = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.DeviceStatusUpdated")

    public static let DeviceBatteryLevelUpdated = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.BatteryLevelUpdated")
}
