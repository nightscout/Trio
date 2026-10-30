import CoreBluetooth
import Foundation
import os

/// Generic bluetoothtransmitter class that handles scanning, connect, discover services, discover characteristics, subscribe to receive characteristic, reconnect.
///
/// - the connection will be set up and a subscribe to a characteristic will be done
/// - a heartbeat function is called each time there's a disconnect (needed for Dexcom) or if there's data received on the receive characteristic
/// - the class does nothing with the data itself
class BluetoothTransmitter: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - private properties

    /// the address of the transmitter.
    private let deviceAddress: String

    /// services to be discovered
    private let servicesCBUUIDs: [CBUUID]

    /// receive characteristic to which we should subcribe in order to awake the app when the tarnsmitter sends data
    private let CBUUID_ReceiveCharacteristic: String

    /// centralManager
    private var centralManager: CBCentralManager?

    /// the receive Characteristic
    private var receiveCharacteristic: CBCharacteristic?

    /// peripheral, gets value during connect
    private(set) var peripheral: CBPeripheral?

    /// to be called when data is received or if there's a disconnect, this is the actual heartbeat.
    private let heartbeat: () -> Void

    // MARK: - Initialization

    /// - parameters:
    ///     - deviceAddress : the bluetooth Mac address
    ///     - one serviceCBUUID: as string, this is the service to be discovered
    ///     - CBUUID_Receive: receive characteristic uuid as string, to which subscribe should be done
    ///     - heartbeat  : function to call when data is received on the receive characteristic or when there's a disconnect
    init(deviceAddress: String, servicesCBUUID: String, CBUUID_Receive: String, heartbeat: @escaping () -> Void) {
        servicesCBUUIDs = [CBUUID(string: servicesCBUUID)]

        CBUUID_ReceiveCharacteristic = CBUUID_Receive

        self.deviceAddress = deviceAddress

        self.heartbeat = heartbeat

        let cBCentralManagerOptionRestoreIdentifierKeyToUse = "Loop-" + deviceAddress

        super.init()

        debug(.cgm, "Creating Bluetooth central for heartbeat transmitter")

        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                CBCentralManagerOptionRestoreIdentifierKey: cBCentralManagerOptionRestoreIdentifierKeyToUse
            ]
        )

        // connect to the device
        connect()
    }

    // MARK: - De-initialization

    deinit {
        // disconnect the device
        disconnect()
    }

    // MARK: - public functions

    /// will try to connect to the device, first by calling retrievePeripherals, if peripheral not known, then by calling startScanning
    func connect() {
        if !retrievePeripherals(centralManager!) {
            startScanning()
        }
    }

    /// disconnect the device
    func disconnect() {
        if let peripheral = peripheral {
            info(.cgm, "Disconnecting heartbeat transmitter")

            centralManager!.cancelPeripheralConnection(peripheral)
        }
    }

    /// stops scanning
    func stopScanning() {
        debug(.cgm, "Stopped scanning for heartbeat transmitter")

        centralManager!.stopScan()
    }

    /// calls setNotifyValue for characteristic with value enabled
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {
        if let peripheral = peripheral {
            debug(.cgm, "Heartbeat transmitter notify \(enabled) for characteristic \(characteristic.uuid.uuidString)")
            peripheral.setNotifyValue(enabled, for: characteristic)

        } else {
            debug(.cgm, "Heartbeat transmitter notify not set: no peripheral")
        }
    }

    // MARK: - fileprivate functions

    /// start bluetooth scanning for device
    fileprivate func startScanning() {
        if centralManager!.state == .poweredOn {
            debug(.cgm, "Scanning for heartbeat transmitter")

            centralManager!.scanForPeripherals(withServices: nil, options: nil)

        } else {
            debug(.cgm, "Heartbeat transmitter scan not started: Bluetooth is not powered on")
        }
    }

    /// stops scanning and connect. To be called after diddiscover
    fileprivate func stopScanAndconnect(to peripheral: CBPeripheral) {
        centralManager!.stopScan()

        self.peripheral = peripheral

        peripheral.delegate = self

        if peripheral.state == .disconnected {
            debug(.cgm, "Connecting to heartbeat transmitter")

            centralManager!.connect(peripheral, options: nil)

        } else {
            debug(.cgm, "Heartbeat transmitter already connected")

            centralManager(centralManager!, didConnect: peripheral)
        }
    }

    /// try to connect to peripheral to which connection was successfully done previously, and that has a uuid that matches the stored deviceAddress. If such peripheral exists, then try to connect, it's not necessary to start scanning. iOS will connect as soon as the peripheral comes in range, or bluetooth status is switched on, whatever is necessary
    ///
    /// the result of the attempt to try to find such device, is returned
    fileprivate func retrievePeripherals(_ central: CBCentralManager) -> Bool {
        debug(.cgm, "Looking up known heartbeat transmitter")

        if let uuid = UUID(uuidString: deviceAddress) {
            let peripheralArr = central.retrievePeripherals(withIdentifiers: [uuid])

            if !peripheralArr.isEmpty {
                peripheral = peripheralArr[0]

                if let peripheral = peripheral {
                    debug(.cgm, "Known heartbeat transmitter found, connecting")

                    peripheral.delegate = self

                    central.connect(peripheral, options: nil)

                    return true

                } else {
                    debug(.cgm, "Known heartbeat transmitter missing")
                }
            } else {
                debug(.cgm, "Known heartbeat transmitter not available, will scan")
            }

        } else {
            debug(.cgm, "No stored heartbeat transmitter ID, will scan")
        }

        return false
    }

    // MARK: - methods from protocols CBCentralManagerDelegate, CBPeripheralDelegate

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        // check if stored address not nil, in which case we already connected before and we expect a full match with the already known device name
        if peripheral.identifier.uuidString == deviceAddress {
            debug(.cgm, "Discovered heartbeat transmitter, connecting")

            stopScanAndconnect(to: peripheral)
        }
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        info(.cgm, "Heartbeat transmitter connected")

        peripheral.discoverServices(servicesCBUUIDs)
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        warning(.cgm, "Heartbeat transmitter connection failed, retrying", error: error)

        centralManager!.connect(peripheral, options: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        debug(.cgm, "Bluetooth state for heartbeat transmitter: \(central.state.rawValue)")

        /// in case status changed to powered on and if device address known then try to retrieveperipherals
        if central.state == .poweredOn {
            /// try to connect to device to which connection was successfully done previously, this attempt is done by callling retrievePeripherals(central)
            _ = retrievePeripherals(central)
        }
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error: Error?) {
        info(.cgm, "Heartbeat transmitter disconnected")

        // call heartbeat, useful for Dexcom transmitters, after a disconnect, then there's probably a new reading available
        heartbeat()

        if let error = error {
            warning(.cgm, "Heartbeat transmitter disconnect reported an error", error: error)
        }

        // if self.peripheral == nil, then a manual disconnect or something like that has occured, no need to reconnect
        // otherwise disconnect occurred because of other (like out of range), so let's try to reconnect
        if let ownPeripheral = peripheral {
            debug(.cgm, "Reconnecting heartbeat transmitter")

            centralManager!.connect(ownPeripheral, options: nil)

        } else {
            debug(.cgm, "Not reconnecting heartbeat transmitter: disconnected on purpose")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        debug(.cgm, "Heartbeat transmitter services discovered")

        if let error = error {
            warning(.cgm, "Heartbeat transmitter service discovery failed", error: error)
        }

        if let services = peripheral.services {
            for service in services {
                debug(.cgm, "Discovering characteristics for service \(service.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        } else {
            disconnect()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        debug(.cgm, "Characteristics discovered for service \(service.uuid.uuidString)")

        if let error = error {
            warning(.cgm, "Heartbeat transmitter characteristic discovery failed", error: error)
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == CBUUID(string: CBUUID_ReceiveCharacteristic) {
                    debug(.cgm, "Heartbeat transmitter receive characteristic found")

                    receiveCharacteristic = characteristic

                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }

        } else {
            warning(.cgm, "Heartbeat transmitter service has no characteristics")
        }
    }

    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            warning(
                .cgm,
                "Heartbeat transmitter notify update failed for characteristic \(characteristic.uuid.uuidString)",
                error: error
            )
        }
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor _: CBCharacteristic, error _: Error?) {
        debug(.cgm, "Heartbeat transmitter sent data")

        // call heartbeat
        heartbeat()
    }

    func centralManager(
        _: CBCentralManager,
        willRestoreState _: [String: Any]
    ) {
        // willRestoreState must be defined, otherwise the app would crash (because the centralManager was created with a CBCentralManagerOptionRestoreIdentifierKey)
        // even if it's an empty function
        // trace is called here because it allows us to see in the issue reports if there was a restart after app crash or removed from memory - in all other cases (force closed by user) this function is not called

        debug(.cgm, "Bluetooth state restored for heartbeat transmitter")
    }
}

// MARK: - UserDefaults

extension UserDefaults {
    public enum BTKey: String {
        /// used as local copy of cgmTransmitterDeviceAddress, will be compared regularly against value in shared UserDefaults
        ///
        /// this is the local stored (ie not shared with xDrip4iOS) copy of the cgm (bluetooth) device address
        case cgmTransmitterDeviceAddress = "com.loopkit.Loop.cgmTransmitterDeviceAddress"
    }

    /// used as local copy of cgmTransmitterDeviceAddress, will be compared regularly against value in shared UserDefaults
    var cgmTransmitterDeviceAddress: String? {
        get {
            string(forKey: BTKey.cgmTransmitterDeviceAddress.rawValue)
        }
        set {
            set(newValue, forKey: BTKey.cgmTransmitterDeviceAddress.rawValue)
        }
    }
}
