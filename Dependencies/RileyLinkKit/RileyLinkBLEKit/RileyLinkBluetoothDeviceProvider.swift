//
//  RileyLinkDeviceManager.swift
//  RileyLinkBLEKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import CoreBluetooth
import os.log
import LoopKit

public class RileyLinkBluetoothDeviceProvider: NSObject {
    private let log = OSLog(category: "RileyLinkDeviceManager")

    // Isolated to centralQueue
    private var central: CBCentralManager!

    private let centralQueue = DispatchQueue(label: "com.rileylink.RileyLinkBLEKit.BluetoothManager.centralQueue", qos: .unspecified)

    internal let sessionQueue = DispatchQueue(label: "com.rileylink.RileyLinkBLEKit.RileyLinkDeviceManager.sessionQueue", qos: .unspecified)

    public weak var delegate: RileyLinkDeviceProviderDelegate?

    // Isolated to centralQueue
    private var devices: [RileyLinkBluetoothDevice] = [] {
        didSet {
            NotificationCenter.default.post(name: .ManagerDevicesDidChange, object: self)
        }
    }

    // Isolated to centralQueue
    private var autoConnectIDs: Set<String> {
        didSet {
            delegate?.rileylinkDeviceProvider(self, didChange: RileyLinkConnectionState(autoConnectIDs: autoConnectIDs))
        }
    }

    public var connectingCount: Int {
        return self.autoConnectIDs.count
    }

    // Isolated to centralQueue
    private var isScanningEnabled = false

    public init(autoConnectIDs: Set<String>) {
        self.autoConnectIDs = autoConnectIDs

        super.init()

        centralQueue.sync {
            central = CBCentralManager(
                delegate: self,
                queue: centralQueue,
                options: [
                    CBCentralManagerOptionRestoreIdentifierKey: "com.rileylink.CentralManager"
                ]
            )
        }
    }

    // MARK: - Configuration

    public var idleListeningEnabled: Bool {
        if case .disabled = idleListeningState {
            return false
        } else {
            return true
        }
    }

    public var idleListeningState: RileyLinkBluetoothDevice.IdleListeningState {
        get {
            return lockedIdleListeningState.value
        }
        set {
            lockedIdleListeningState.value = newValue
            centralQueue.async {
                for device in self.devices {
                    device.setIdleListeningState(newValue)
                }
            }
        }
    }
    private let lockedIdleListeningState = Locked(RileyLinkBluetoothDevice.IdleListeningState.disabled)

    public var timerTickEnabled: Bool {
        get {
            return lockedTimerTickEnabled.value
        }
        set {
            lockedTimerTickEnabled.value = newValue
            centralQueue.async {
                for device in self.devices {
                    if device.isConnected {
                        device.setTimerTickEnabled(newValue)
                    }
                }
            }
        }
    }
    private let lockedTimerTickEnabled = Locked(true)
}


// MARK: - Connecting
extension RileyLinkBluetoothDeviceProvider {
    public func getAutoConnectIDs(_ completion: @escaping (_ autoConnectIDs: Set<String>) -> Void) {
        centralQueue.async {
            completion(self.autoConnectIDs)
        }
    }
    
    /// Asks the central manager for its peripheral instance for a given device.
    /// It seems to be possible that this reference changes across a bluetooth reset, and not updating the reference can result in API MISUSE warnings
    ///
    /// - Parameter device: The device to reload
    /// - Returns: The peripheral instance returned by the central manager
    private func reloadPeripheral(for device: RileyLinkBluetoothDevice) -> CBPeripheral? {
        dispatchPrecondition(condition: .onQueue(centralQueue))

        guard let peripheral = central.retrievePeripherals(withIdentifiers: [device.peripheralIdentifier]).first else {
            return nil
        }

        device.setPeripheral(peripheral)
        return peripheral
    }

    private var hasDiscoveredAllAutoConnectDevices: Bool {
        dispatchPrecondition(condition: .onQueue(centralQueue))

        return autoConnectIDs.isSubset(of: devices.map { $0.peripheralIdentifier.uuidString })
    }

    private func autoConnectDevices() {
        dispatchPrecondition(condition: .onQueue(centralQueue))

        for device in devices where autoConnectIDs.contains(device.peripheralIdentifier.uuidString) {
            log.info("Attempting reconnect to %@", String(describing: device))
            connect(device)
        }
    }

    private func addPeripheral(_ peripheral: CBPeripheral, rssi: Int? = nil) {
        dispatchPrecondition(condition: .onQueue(centralQueue))

        var device: RileyLinkBluetoothDevice! = devices.first(where: { $0.peripheralIdentifier == peripheral.identifier })

        if let device = device {
            device.setPeripheral(peripheral)
        } else {
            device = RileyLinkBluetoothDevice(peripheralManager: PeripheralManager(peripheral: peripheral, configuration: .rileyLink, centralManager: central, queue: sessionQueue), rssi: rssi)
            if peripheral.state == .connected {
                device.setTimerTickEnabled(timerTickEnabled)
                device.setIdleListeningState(idleListeningState)
            }

            devices.append(device)

            log.info("Created device for peripheral %@", peripheral)
        }

        if autoConnectIDs.contains(peripheral.identifier.uuidString) {
            central.connectIfNecessary(peripheral)
        }
    }
}

extension RileyLinkBluetoothDeviceProvider: RileyLinkDeviceProvider {
    public func connect(_ device: RileyLinkDevice) {
        centralQueue.async {
            self.autoConnectIDs.insert(device.peripheralIdentifier.uuidString)

            guard let peripheral = self.reloadPeripheral(for: device as! RileyLinkBluetoothDevice) else {
                return
            }

            self.central.connectIfNecessary(peripheral)
        }
    }

    public func disconnect(_ device: RileyLinkDevice) {
        centralQueue.async {
            self.autoConnectIDs.remove(device.peripheralIdentifier.uuidString)

            guard let peripheral = self.reloadPeripheral(for: device as! RileyLinkBluetoothDevice) else {
                return
            }

            self.central.cancelPeripheralConnectionIfNecessary(peripheral)
        }
    }

    public func getDevices(_ completion: @escaping (_ devices: [RileyLinkDevice]) -> Void) {
        centralQueue.async {
            completion(self.devices)
        }
    }

    public func deprioritize(_ device: RileyLinkDevice, completion: (() -> Void)? = nil) {
        centralQueue.async {
            self.devices.deprioritize(device as! RileyLinkBluetoothDevice)
            completion?()
        }
    }
    
    public func setScanningEnabled(_ enabled: Bool) {
        centralQueue.async {
            self.isScanningEnabled = enabled

            if case .poweredOn = self.central.state {
                if enabled {
                    self.central.scanForPeripherals()
                } else if self.central.isScanning {
                    self.central.stopScan()
                }
            }
        }
    }

    public func assertIdleListening(forcingRestart: Bool) {
        centralQueue.async {
            for device in self.devices {
                device.assertIdleListening(forceRestart: forcingRestart)
            }
        }
    }

    public func shouldConnect(to deviceID: String) -> Bool {
        return self.autoConnectIDs.contains(deviceID)
    }
}

extension Array where Element == RileyLinkBluetoothDevice {
    mutating func deprioritize(_ element: Element) {
        if let index = self.firstIndex(where: { $0 === element }) {
            self.swapAt(index, self.count - 1)
        }
    }
}


// MARK: - Delegate methods called on `centralQueue`
extension RileyLinkBluetoothDeviceProvider: CBCentralManagerDelegate {
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        log.default("%@", #function)

        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            return
        }

        for peripheral in peripherals {
            addPeripheral(peripheral)
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.default("%@: %@", #function, central.state.description)
        if case .poweredOn = central.state {
            autoConnectDevices()

            if isScanningEnabled || !hasDiscoveredAllAutoConnectDevices {
                central.scanForPeripherals()
            } else if central.isScanning {
                central.stopScan()
            }
        }

        for device in devices {
            device.centralManagerDidUpdateState(central)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log.default("Discovered %@ at %@", peripheral, RSSI)

        addPeripheral(peripheral, rssi: Int(truncating: RSSI))

        // TODO: Should we keep scanning? There's no UI to remove a lost RileyLink, which could result in a battery drain due to indefinite scanning.
        if !isScanningEnabled && central.isScanning && hasDiscoveredAllAutoConnectDevices {
            log.default("All peripherals discovered")
            central.stopScan()
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Notify the device so it can begin configuration
        for device in devices where device.peripheralIdentifier == peripheral.identifier {
            device.centralManager(central, didConnect: peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        for device in devices where device.peripheralIdentifier == peripheral.identifier {
            device.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
        }

        autoConnectDevices()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.error("%@: %@: %@", #function, peripheral, String(describing: error))

        for device in devices where device.peripheralIdentifier == peripheral.identifier {
            device.centralManager(central, didFailToConnect: peripheral, error: error)
        }

        autoConnectDevices()
    }
}


extension RileyLinkBluetoothDeviceProvider {
    public override var debugDescription: String {
        var report = [
            "## RileyLinkDeviceManager",
            "central: \(central!)",
            "autoConnectIDs: \(autoConnectIDs)",
            "timerTickEnabled: \(timerTickEnabled)",
            "idleListeningState: \(idleListeningState)"
        ]

        for device in devices {
            report.append(String(reflecting: device))
            report.append("")
        }

        return report.joined(separator: "\n\n")
    }
}


extension Notification.Name {
    public static let ManagerDevicesDidChange = Notification.Name("com.rileylink.RileyLinkBLEKit.DevicesDidChange")
}

extension RileyLinkBluetoothDeviceProvider {
    public static let autoConnectIDsStateKey = "com.rileylink.RileyLinkBLEKit.AutoConnectIDs"
}

