//
//  MiaoMiaoManager.swift
//  LibreMonitor
//
//  Created by Uwe Petersen on 10.03.18.
//  Copyright © 2018 Uwe Petersen. All rights reserved.
//

import CoreBluetooth
import Foundation
import HealthKit
import os.log
import UIKit
import LoopKit

public enum BluetoothmanagerState: String {
    case Unassigned = "Unassigned"
    case Scanning = "Scanning"
    case Disconnected = "Disconnected"
    case DelayedReconnect = "Will soon reconnect"
    case DisconnectingDueToButtonPress = "Disconnecting due to button press"
    case Connecting = "Connecting"
    case Connected = "Connected"
    case Notifying = "Notifying"
    case powerOff = "powerOff"
    case UnknownDevice = "UnknownDevice"
}



public protocol LibreTransmitterDelegate: AnyObject {
    // Can happen on any queue
    func libreDeviceStateChanged(_ state: BluetoothmanagerState)
    func libreDeviceReceivedMessage(_ txFlags: UInt8, payloadData: Data) // actionable
    func libreDeviceLogMessage(payload: String, type: DeviceLogEntryType) //just log
    // Will always happen on managerQueue
    func libreTransmitterDidUpdate(with sensorData: SensorData, and Device: LibreTransmitterMetadata)
    func libreSensorDidUpdate(with bleData: Libre2.LibreBLEResponse, and Device: LibreTransmitterMetadata)
    func libreSensorDidUpdate(with error: LibreError)

    func noLibreTransmitterSelected()
    func libreManagerDidRestoreState(found peripherals: [CBPeripheral], connected to: CBPeripheral?)
}

extension LibreTransmitterDelegate {
    func noLibreTransmitterSelected() {}
    public func libreManagerDidRestoreState(found peripherals: [CBPeripheral], connected to: CBPeripheral?) {}

}

public final class LibreTransmitterProxyManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, LibreTransmitterDelegate {
   
    
    public func libreSensorDidUpdate(with bleData: Libre2.LibreBLEResponse, and Device: LibreTransmitterMetadata) {
        dispatchToDelegate { manager in
            manager.delegate?.libreSensorDidUpdate(with: bleData, and: Device)
        }
    }
    public func libreSensorDidUpdate(with error: LibreError) {
        dispatchToDelegate { manager in
            manager.delegate?.libreSensorDidUpdate(with: error)
        }
    }

    public func libreManagerDidRestoreState(found peripherals: [CBPeripheral], connected to: CBPeripheral?) {
        dispatchToDelegate { manager in
            manager.delegate?.libreManagerDidRestoreState(found: peripherals, connected: to)
        }
    }

    public func noLibreTransmitterSelected() {
        dispatchToDelegate { manager in
            manager.delegate?.noLibreTransmitterSelected()
        }
    }

    public func libreDeviceStateChanged(_ state: BluetoothmanagerState) {

        logger.debug("libreTransmitterStateChanged delegating")
        dispatchToDelegate { manager in
           manager.delegate?.libreDeviceStateChanged(state)
        }
    }
    
    public func libreDeviceLogMessage(payload: String, type: DeviceLogEntryType) {
        logger.debug("libreDeviceLogMessage delegating")
        dispatchToDelegate { manager in
            manager.delegate?.libreDeviceLogMessage(payload: payload, type: type)
        }
    }

    public func libreDeviceReceivedMessage(_ txFlags: UInt8, payloadData: Data) {

        logger.debug("libreTransmitterReceivedMessage delegating")
        dispatchToDelegate { manager in
            manager.delegate?.libreDeviceReceivedMessage(txFlags, payloadData: payloadData)
        }
    }

    public func libreTransmitterDidUpdate(with sensorData: SensorData, and Device: LibreTransmitterMetadata) {
        self.metadata = Device
        self.sensorData = sensorData

        logger.debug("libreTransmitterDidUpdate delegating")
        dispatchToDelegate { manager in
            manager.delegate?.libreTransmitterDidUpdate(with: sensorData, and: Device)
        }
    }

    // MARK: - Properties
    private var wantsToTerminate = false
    // private var lastConnectedIdentifier : String?

    var activePlugin: LibreTransmitterProxyProtocol? {
        didSet {

            logger.debug("activePlugin changed from \(oldValue.debugDescription) to \(self.activePlugin.debugDescription)")

        }
    }

    var activePluginType: LibreTransmitterProxyProtocol.Type? {
        activePlugin?.staticType
    }

    var shortTransmitterName: String? {
        activePluginType?.shortTransmitterName
    }

    fileprivate lazy var logger = Logger(forType: Self.self)
    var metadata: LibreTransmitterMetadata?

    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral?
    //    var slipBuffer = SLIPBuffer()
    var writeCharacteristic: CBCharacteristic?

    var sensorData: SensorData?

    public var identifier: UUID? {
        peripheral?.identifier
    }

    private let managerQueue = DispatchQueue(label: "com.loopkit.librebluetoothManagerQueue", qos: .utility)
    private let delegateQueue = DispatchQueue(label: "com.loopkit.libredelegateQueue", qos: .utility)

    fileprivate var serviceUUIDs: [CBUUID]? {
        activePluginType?.serviceUUID.map { $0.value }
    }
    fileprivate var writeCharachteristicUUID: CBUUID? {
        activePluginType?.writeCharacteristic?.value
    }
    fileprivate var notifyCharacteristicUUID: CBUUID? {
        activePluginType?.notifyCharacteristic?.value
    }

    weak var delegate: LibreTransmitterDelegate? {
        didSet {
           dispatchToDelegate { manager in
                // Help delegate initialize by sending current state directly after delegate assignment
                manager.delegate?.libreDeviceStateChanged(self.state)
           }
        }
    }

    public private(set) var state: BluetoothmanagerState = .Unassigned {
        didSet {
            dispatchToDelegate { manager in
                // Help delegate initialize by sending current state directly after delegate assignment
                manager.delegate?.libreDeviceStateChanged(self.state)
            }
        }
    }
    public var connectionStateString: String {
        self.state.rawValue
    }

    public func dispatchToDelegate( _ closure :@escaping  (_ aself: LibreTransmitterProxyManager) -> Void ) {
        delegateQueue.async { [weak self] in
            if let self {
                closure(self)
            }
        }
    }

    // MARK: - Methods

    override init() {
        super.init()
        logger.debug("LibreTransmitterProxyManager called")
        managerQueue.sync {
            let restoreID = "LibreTransmitterBluetoothRestoreIdentifierKey"
            centralManager = CBCentralManager(delegate: self, queue: managerQueue, options: [CBCentralManagerOptionShowPowerAlertKey: true, CBCentralManagerOptionRestoreIdentifierKey: restoreID])
        }
    }

    func scanForDevices() {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        logger.debug("Scan for bluetoothdevice while internal state= \(String(describing: self.state)), bluetoothstate=\(String(describing: self.centralManager.state))")

        guard centralManager.state == .poweredOn else {
            return
        }

        logger.debug("Before scan for libre bluetooth device while central manager state was  \(String(describing: self.centralManager.state.rawValue)))")

        let scanForAllServices = false

        // this will search for all peripherals. Guaranteed to work
        if scanForAllServices {

            logger.debug("Scanning for all services:")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            // This is what we should have done
            // Here we optimize by scanning only for relevant services
            // However, this doesn't work correctly with both miaomiao and bubble
            let services = LibreTransmitters.all.getServicesForDiscovery()
            logger.debug("Scanning for specific services: \(String(describing: services.map { $0.uuidString }))")
            centralManager.scanForPeripherals(withServices: services, options: nil)

        }

        state = .Scanning
    }

    private func reset() {
        logger.debug("manager is resetting the activeplugin")

        self.activePlugin?.reset()
    }

    private func connect(force forceConnect: Bool = false, advertisementData: [String: Any]?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("connect while state: \(String(describing: self.state.rawValue))")
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        if state == .DisconnectingDueToButtonPress && !forceConnect {

            logger.debug("Connect aborted, user has actively disconnected and a reconnect was not forced")
            return
        }

        if let peripheral = self.peripheral {
            peripheral.delegate = self

            if activePlugin?.canSupportPeripheral(peripheral) == true {
                // when reaching this part,
                // we are sure the peripheral is reconnecting and therefore needs reset

                logger.debug("Connecting to known device with known plugin")

                self.reset()

                centralManager.connect(peripheral, options: nil)
                state = .Connecting
            } else if let plugin = LibreTransmitters.getSupportedPlugins(peripheral)?.first {
                self.activePlugin = plugin.init(delegate: self, advertisementData: advertisementData)

                logger.debug("Connecting to new device with known plugin")

                // only connect to devices we can support (i.e. devices that has a suitable plugin)
                centralManager.connect(peripheral, options: nil)
                state = .Connecting
            } else {
                state = .UnknownDevice
            }
        }
    }

    func disconnectManually() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))
        logger.debug("Disconnect manually while state \(String(describing: self.state))" )

        managerQueue.sync {
            switch self.state {
            case .Connected, .Connecting, .Notifying, .Scanning:
                self.state = .DisconnectingDueToButtonPress  // to avoid reconnect in didDisconnetPeripheral

                self.wantsToTerminate = true
            default:
                break
            }

            if centralManager.isScanning {
                logger.debug("Stopping scan")
                centralManager.stopScan()
            }
            if let peripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    // MARK: - CBCentralManagerDelegate

     public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Central Manager did update state to \(String(describing: central.state.rawValue))")

        switch central.state {
        case .poweredOff:
            state = .powerOff
        case .resetting, .unauthorized, .unknown, .unsupported:
            logger.debug("Central Manager was either .poweredOff, .resetting, .unauthorized, .unknown, .unsupported:  \(String(describing: central.state))")
            state = .Unassigned

            if central.state == .resetting, let peripheral = self.peripheral {
                logger.debug("Central Manager resetting, will cancel peripheral connection")
                central.cancelPeripheralConnection(peripheral)
                self.peripheral = nil
            }

            if central.isScanning {
                central.stopScan()
            }
        case .poweredOn:

            if state == .DisconnectingDueToButtonPress {
                logger.debug("Central Manager was powered on but sensorstate was DisconnectingDueToButtonPress: \(String(describing: central.state))")

                return
            }

            logger.debug("Central Manager was powered on")

            // not sure if needed, but can be helpful when state is restored
            if let peripheral, delegate != nil {
                // do not scan if already connected
                switch peripheral.state {
                case .disconnected, .disconnecting:
                    logger.debug("Central Manager was powered on, peripheral state is disconnecting")
                    self.connect(advertisementData: nil)
                case .connected, .connecting:
                    logger.debug("Central Manager was powered on, peripheral state is connected/connecting, renewing plugin")

                    // This is necessary
                    // Normally the connect() method would have set the correct plugin,
                    // however when we hit this path, it is likely a state restoration
                    if self.activePlugin == nil || self.activePlugin?.canSupportPeripheral(peripheral) == false {
                        let plugin = LibreTransmitters.getSupportedPlugins(peripheral)?.first
                        self.activePlugin = plugin?.init(delegate: self, advertisementData: nil)

                        logger.debug("Central Manager was powered on, peripheral state is connected/connecting, stopping scan")
                        if central.isScanning && peripheral.state == .connected {
                            central.stopScan()
                        }
                        if peripheral.delegate == nil {
                            logger.debug("Central Manager was powered on, peripheral delegate was nil")

                        }
                    }

                    if let serviceUUIDs, !serviceUUIDs.isEmpty {
                        peripheral.discoverServices(serviceUUIDs) // good practice to just discover the services, needed
                    } else {
                        logger.debug("Central Manager was powered on, could not discover services")

                    }

                default:
                    logger.debug("Central Manager already connected")
                }
            } else {

                if let preselected = UserDefaults.standard.preSelectedDevice,
                   let uuid = UUID(uuidString: preselected),
                   let newPeripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first,
                   let plugin = LibreTransmitters.getSupportedPlugins(newPeripheral)?.first {
                    logger.debug("Central Manager was powered on, directly connecting to already known peripheral \(newPeripheral): \(String(describing: self.state))")
                    self.peripheral = newPeripheral
                    self.peripheral?.delegate = self

                    self.activePlugin = plugin.init(delegate: self, advertisementData: nil)

                    managerQueue.async {
                        self.state = .Connecting
                        self.centralManager.connect(newPeripheral, options: nil)

                    }

                } else {
                    // state should be nassigned here
                    logger.debug("Central Manager was powered on, scanningfordevice: \(String(describing: self.state))")
                    scanForDevices() // power was switched on, while app is running -> reconnect.

                }

            }
        @unknown default:
            fatalError("libre bluetooth state unhandled")
        }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Central Manager will restore state to \(String(describing: dict.debugDescription))")

        guard self.peripheral == nil else {
            logger.debug("Central Manager tried to restore state while already connected")
            return
        }

        guard let preselected = UserDefaults.standard.preSelectedDevice else {
            logger.debug("Central Manager tried to restore state but no device was preselected")
            return
        }

        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            logger.debug("Central Manager tried to restore state but no peripheral found")
            self.scanForDevices()
            return
        }

        defer {
            self.libreManagerDidRestoreState(found: peripherals, connected: self.peripheral)
        }

        let restorablePeripheral = peripherals.first(where: { $0.identifier.uuidString == preselected })

        guard let peripheral = restorablePeripheral else {
            return
        }

        self.peripheral = peripheral
        peripheral.delegate = self

        switch peripheral.state {
        case .disconnected, .disconnecting:
            logger.debug("Central Manager tried to restore state from disconnected peripheral")
            state = .Disconnected
            self.connect(advertisementData: nil)
        case .connecting:
            logger.debug("Central Manager tried to restore state from connecting peripheral")
            state = .Connecting
        case .connected:
            logger.debug("Central Manager tried to restore state from connected peripheral, letting centralManagerDidUpdateState() do the rest of the job")
            // the idea here is to let centralManagerDidUpdateState() do the heavy lifting
            // after all, we did assign the periheral.delegate to self earlier

            // that means the following is not necessary:
            // state = .Connected
            // peripheral.discoverServices(serviceUUIDs) // good practice to just discover the services, needed
        @unknown default:
            fatalError("Failed due to unkown default, Uwe!")
        }
    }
    
    private func verifyLibre2ManufacturerData(peripheral: CBPeripheral, selectedUid: Data ,advertisementData: [String: Any]) -> Bool {
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            logger.debug("manufacturerData was not retrieved")
            return false
        }

        guard manufacturerData.count == 8 else {
            logger.debug("manufacturerData was of incorrect size: \(manufacturerData.count)")
            return false
        }
         logger.debug("manufacturerdata is: \(manufacturerData.hex)")

        var foundUUID = manufacturerData.subdata(in: 2..<8)
        foundUUID.append(contentsOf: [0x07, 0xe0])
        
        logger.debug("ManufacturerData: \(manufacturerData.hex), found uid: \(foundUUID.hex)")

        guard foundUUID == selectedUid && Libre2DirectTransmitter.canSupportPeripheral(peripheral) else {
            return false
        }
        
        return true
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        logger.debug("Did discover peripheral while state \(String(describing: self.state.rawValue)) with name: \(String(describing: peripheral.name)), wantstoterminate?: \(self.wantsToTerminate)")

        // Libre2:
        // during setup, we find the uid by scanning via nfc
        // first time connecting to a libre2 sensor via bluetooth we don't know its peripheral identifier
        // but since the uid is also part of the libre 2bluetooth advertismentdata we trade uid for

         if let selectedUid = UserDefaults.standard.preSelectedUid {
            logger.debug("Was asked to connect preselected libre2 by uid: \(selectedUid.hex), discovered devicename is: \(String(describing: peripheral.name))")

             let sensor = UserDefaults.standard.preSelectedSensor
             logger.debug("preselected sensor is: \(String(describing:sensor))")
             
             
             if !verifyLibre2ManufacturerData(peripheral: peripheral, selectedUid: selectedUid, advertisementData: advertisementData) {
                 logger.debug("failed Verifiying libre2 connection using manufacturerData")
                 return
             }

            // next time we search via bluetooth, let's identify the sensor with its bluetooth identifier
            UserDefaults.standard.preSelectedUid = nil
            UserDefaults.standard.preSelectedDevice = peripheral.identifier.uuidString



            logger.debug("Did connect to preselected \(String(describing: peripheral.name)) with identifier \(String(describing: peripheral.identifier.uuidString)) and uid \(selectedUid.hex)")
            self.peripheral = peripheral

            self.connect(force: true, advertisementData: advertisementData)

            return

        }

        if let preselected = UserDefaults.standard.preSelectedDevice {
            if peripheral.identifier.uuidString == preselected {
                logger.debug("Did connect to preselected \(String(describing: peripheral.name)) with identifier \(String(describing: peripheral.identifier.uuidString))")
                self.peripheral = peripheral

                self.connect(force: true, advertisementData: advertisementData)
            } else {
                logger.info(
                """
                Did not connect to \(String(describing: peripheral.name)),
                with identifier \(String(describing: peripheral.identifier.uuidString)),
                because another device with identifier \(preselected) was selected
                """)
            }

            return
        } else {
            self.noLibreTransmitterSelected()
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        logger.debug("Did connect peripheral while state \(String(describing: self.state.rawValue)) with name: \(String(describing: peripheral.name))")
        if central.isScanning {
            central.stopScan()
        }
        state = .Connected
        // self.lastConnectedIdentifier = peripheral.identifier.uuidString
        // Discover all Services. This might be helpful if writing is needed some time
        peripheral.discoverServices(serviceUUIDs)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        logger.debug("Did fail to connect peripheral while state: \(String(describing: self.state.rawValue))")
        if let error {
            logger.error("Did fail to connect peripheral error: \(error.localizedDescription)")
        }
        state = .Disconnected

        self.reconnect()
    }

    private func reconnect() {
        let withDelay = self.activePluginType?.requiresDelayedReconnect == true
        if withDelay {
            delayedReconnect()
        } else {
            reconnectImmediately()
        }
    }

    private func reconnectImmediately() {
        self.connect(advertisementData: nil)
    }

    private func delayedReconnect(_ seconds: Double = 7) {
        state = .DelayedReconnect

        logger.debug("Will reconnect peripheral in  \(String(describing: seconds)) seconds")
        self.reset()
        // attempt to avoid IOS killing app because of cpu usage.
        // postpone connecting for x seconds
        DispatchQueue.global(qos: .utility).async { [weak self] in
            Thread.sleep(forTimeInterval: seconds)
            self?.managerQueue.sync {
                self?.connect(advertisementData: nil)
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        logger.debug("Did disconnect peripheral while state: \(String(describing: self.state.rawValue)))")
        if let error {
            logger.error("Did disconnect peripheral error: \(error.localizedDescription)")
        }

        switch state {
        case .DisconnectingDueToButtonPress:
            state = .Disconnected
            self.wantsToTerminate = true

        default:
            state = .Disconnected
            self.reconnect()

            //    scanForMiaoMiao()
        }
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Did discover services. is plugin nil? \((self.activePlugin == nil ? "nil" : "not nil"))")
        if let error {
            logger.error("Did discover services error: \(error.localizedDescription)")
        }

        if let services = peripheral.services {
            for service in services {
                let toDiscover = [writeCharachteristicUUID, notifyCharacteristicUUID].compactMap { $0 }

                logger.debug("Will discover : \(String(describing: toDiscover.count)) Characteristics for service \(String(describing: service.debugDescription))")

                if !toDiscover.isEmpty {
                    peripheral.discoverCharacteristics(toDiscover, for: service)

                    logger.debug("Did discover service: \(String(describing: service.debugDescription))")
                }
            }
        }
    }

    func didDiscoverNotificationCharacteristic(_ peripheral: CBPeripheral, notifyCharacteristic characteristic: CBCharacteristic) {

        logger.debug("Did discover characteristic: \(String(describing: characteristic.debugDescription)) and asking activeplugin to handle it as a notification Characteristic")

        self.activePlugin?.didDiscoverNotificationCharacteristic(peripheral, notifyCharacteristic: characteristic)

    }

    func didDiscoverWriteCharacteristic(_ peripheral: CBPeripheral, writeCharacteristic characteristic: CBCharacteristic) {
        writeCharacteristic = characteristic
        logger.debug("Did discover characteristic: \(String(describing: characteristic.debugDescription)) and asking activeplugin to handle it as a write Characteristic")
        self.activePlugin?.didDiscoverWriteCharacteristics(peripheral, writeCharacteristics: characteristic)

    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        logger.debug("Did discover characteristics for service \(String(describing: peripheral.name))")

        if let error {
            logger.error("Did discover characteristics for service error: \(error.localizedDescription)")
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {

                logger.debug("Did discover characteristic: \(String(describing: characteristic.debugDescription))")
                if characteristic.properties.intersection(.notify) == .notify && characteristic.uuid == notifyCharacteristicUUID {
                    didDiscoverNotificationCharacteristic(peripheral, notifyCharacteristic: characteristic)
                }
                if characteristic.uuid == writeCharachteristicUUID {
                    didDiscoverWriteCharacteristic(peripheral, writeCharacteristic: characteristic)
                }
            }
        } else {
            logger.debug("Discovered characteristics, but no characteristics listed. There must be some error.")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Did update notification state for characteristic: \(String(describing: characteristic.debugDescription))")

        if let error {
            logger.error("Peripheral did update notification state for characteristic: \(error.localizedDescription) with error")
        } else {
            self.reset()
            requestData()
        }
        state = .Notifying
    }

    private var lastNotifyUpdate: Date?
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        let now = Date()

        // We can expect thedevices to complete well within 5 seconds for all the telegrams combined in a session
        // it is therefore reasonable to expect the time between one telegram
        // to the other in the same session to be well within 6 seconds
        // this path will be hit when a telegram for some reason is dropped
        // in a session. Or that the user disconnecting and reconnecting during a transmission
        // By resetting here we ensure that the rxbuffer doesn't leak over into the next session
        // Leaking over into the next session, is however not a problem for consitency as we always check the CRC's anyway
        if let lastNotifyUpdate = self.lastNotifyUpdate, now > lastNotifyUpdate.addingTimeInterval(6) {
            logger.debug("there hasn't been any traffic to  the \((self.activePluginType?.shortTransmitterName).debugDescription) plugin for more than 10 seconds, so we reset now")
            self.reset()
        }

        logger.debug("Did update value for characteristic: \(String(describing: characteristic.debugDescription))")

        self.lastNotifyUpdate = now

        if let error {
            logger.error("Characteristic update error: \(error.localizedDescription)")
        } else {
            if characteristic.uuid == notifyCharacteristicUUID, let value = characteristic.value {
                if self.activePlugin == nil {
                    logger.error("Characteristic update error: activeplugin was nil")
                }
                self.activePlugin?.updateValueForNotifyCharacteristics(value, peripheral: peripheral, writeCharacteristic: writeCharacteristic)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        logger.debug("Did Write value \(String(describing: characteristic.value?.hexEncodedString())) for characteristic \(String(characteristic.debugDescription))")
        self.activePlugin?.didWrite(peripheral, characteristics: characteristic)

    }

    func requestData() {
       guard let peripheral,
            let writeCharacteristic else {
                return
        }
        self.activePlugin?.requestData(writeCharacteristics: writeCharacteristic, peripheral: peripheral)
    }

    deinit {
        self.activePlugin = nil
        self.delegate = nil
        logger.debug("miaomiaomanager deinit called")
    }
}

extension LibreTransmitterProxyManager {
    public var manufacturer: String {
        activePluginType?.manufacturerer ?? "n/a"
    }

    var device: HKDevice? {
        HKDevice(
            name: "MiaomiaoClient",
            manufacturer: manufacturer,
            model: nil, // latestSpikeCollector,
            hardwareVersion: self.metadata?.hardware,
            firmwareVersion: self.metadata?.firmware,
            softwareVersion: nil,
            localIdentifier: identifier?.uuidString,
            udiDeviceIdentifier: nil
        )
    }
}
