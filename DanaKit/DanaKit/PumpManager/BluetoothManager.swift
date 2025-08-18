import CoreBluetooth
import Foundation
import LoopKit

let deviceNameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z]{3}[0-9]{5}[a-zA-Z]{2}$")

public enum ConnectionResult {
    case success
    case requestedPincode(String?)
    case invalidBle5Keys
    case failure(Error)
    case timeout
    case alreadyConnectedAndBusy
}

public struct DanaPumpScan {
    let bleIdentifier: String
    let name: String
    let peripheral: CBPeripheral
}

enum EncryptionType: UInt8 {
    case DEFAULT = 0
    case RSv3 = 1
    case BLE_5 = 2
}

protocol BluetoothManager: AnyObject, CBCentralManagerDelegate {
    var peripheral: CBPeripheral? { get set }
    var peripheralManager: PeripheralManager? { get set }

    var log: DanaLogger { get }

    var manager: CBCentralManager! { get }
    var managerQueue: DispatchQueue { get }
    var pumpManagerDelegate: DanaKitPumpManager? { get set }

    var isConnected: Bool { get }
    var autoConnectUUID: String? { get set }

    var connectionCompletion: ((ConnectionResult) -> Void)? { get set }
    var connectionCallback: [String: (ConnectionResult) -> Void] { get set }

    var devices: [DanaPumpScan] { get set }

    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol)
    func disconnect(_ peripheral: CBPeripheral, force: Bool) -> Void
    func ensureConnected(_ completion: @escaping (ConnectionResult) async -> Void, _ identifier: String) -> Void
}

extension BluetoothManager {
    func startScan() throws {
        guard manager.state == .poweredOn else {
            throw NSError(domain: "Invalid bluetooth state. State: " + String(manager.state.rawValue), code: 0, userInfo: nil)
        }

        guard !manager.isScanning else {
            log.info("Device is already scanning...")
            return
        }

        devices = []

        manager.scanForPeripherals(withServices: [])
        log.info("Started scanning")
    }

    func stopScan() {
        manager.stopScan()
        devices = []

        log.info("Stopped scanning")
    }

    func connect(_ bleIdentifier: String, _ completion: @escaping (ConnectionResult) -> Void) throws {
        guard let identifier = UUID(uuidString: bleIdentifier) else {
            log.error("Invalid identifier - \(bleIdentifier)")
            throw NSError(domain: "Invalid identifier - \(bleIdentifier)", code: -1)
        }

        connectionCompletion = completion

        let peripherals = manager.retrievePeripherals(withIdentifiers: [identifier])
        if let peripheral = peripherals.first {
            DispatchQueue.main.async {
                self.peripheral = peripheral
                self.peripheralManager = PeripheralManager(peripheral, self, self.pumpManagerDelegate!, completion)

                self.manager.connect(peripheral, options: nil)
            }
            return
        }

        autoConnectUUID = bleIdentifier
        try startScan()

        // throw error if device could not be found after 10 sec
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard self.peripheral != nil else {
                throw NSError(domain: "Device is not findable", code: -1)
            }
        }
    }

    func connect(_ peripheral: CBPeripheral, _ completion: @escaping (ConnectionResult) -> Void) {
        if self.peripheral?.state == .connected {
            disconnect(self.peripheral!, force: true)
        }

        manager.connect(peripheral, options: nil)
        connectionCompletion = completion
    }

    func ensureConnected(_ completion: @escaping (ConnectionResult) async -> Void, _ identifier: String = #function) {
        ensureConnected(completion, identifier)
    }

    func resetConnectionCompletion() {
        connectionCompletion = nil
    }

    func finishV3Pairing(_ pairingKey: Data, _ randomPairingKey: Data) throws {
        guard let peripheralManager = self.peripheralManager else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }

        peripheralManager.finishV3Pairing(pairingKey, randomPairingKey)
    }

    func startTimeout(seconds: TimeInterval, _ identifier: String) {
        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard let connectionCallback = self.connectionCallback[identifier] else {
                    // This is amazing, we've done what we must and continue our live :)
                    return
                }

                self.logDeviceCommunication("Dana - Failed to connect: Timeout reached...", type: .connection)
                self.log.error("Failed to connect: Timeout reached...")

                connectionCallback(.timeout)
                self.connectionCallback[identifier] = nil
            } catch {}
        }
    }

    func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        let address = String(format: "%04X", pumpManagerDelegate?.state.bleIdentifier ?? "")
        // Not dispatching here; if delegate queue is blocked, timestamps will be delayed
        pumpManagerDelegate?.pumpDelegate.delegate?.deviceManager(
            pumpManagerDelegate!,
            logEventForDeviceIdentifier: address,
            type: type,
            message: message,
            completion: nil
        )
    }

    func updateInitialState() async {
        guard let pumpManagerDelegate = self.pumpManagerDelegate else {
            log.error("No pumpManager available...")
            return
        }

        guard let peripheral = self.peripheral else {
            log.error("No peripheral available...")
            return
        }

        do {
            log.info("Sending getInitialScreenInformation")
            let initialScreenPacket = generatePacketGeneralGetInitialScreenInformation()
            let resultInitialScreenInformation = try await writeMessage(initialScreenPacket)

            guard resultInitialScreenInformation.success else {
                log.error("Failed to fetch Initial screen...")
                disconnect(peripheral, force: true)
                return
            }

            guard let data = resultInitialScreenInformation.data as? PacketGeneralGetInitialScreenInformation else {
                log.error("No data received (initial screen)...")
                disconnect(peripheral, force: true)
                return
            }

            if data.batteryRemaining == 100, pumpManagerDelegate.state.batteryRemaining != 100 {
                pumpManagerDelegate.state.batteryAge = Date.now
            }

            pumpManagerDelegate.state.reservoirLevel = data.reservoirRemainingUnits
            pumpManagerDelegate.state.batteryRemaining = data.batteryRemaining
            pumpManagerDelegate.state.isPumpSuspended = data.isPumpSuspended
            pumpManagerDelegate.state.isTempBasalInProgress = data.isTempBasalInProgress

            if pumpManagerDelegate.state.basalDeliveryOrdinal != .suspended, data.isPumpSuspended {
                // Suspended has been enabled via the pump
                // We cannot be sure at what point it has been enabled...
                pumpManagerDelegate.state.basalDeliveryDate = Date.now
            }

            pumpManagerDelegate.state.basalDeliveryOrdinal = data.isTempBasalInProgress ? .tempBasal :
                data.isPumpSuspended ? .suspended : .active
            pumpManagerDelegate.state.bolusState = .noBolus

            pumpManagerDelegate.notifyStateDidChange()
        } catch {
            log.error("Error while updating initial state: \(error.localizedDescription)")
        }
    }
}

// MARK: Central manager functions

extension BluetoothManager {
    func bleCentralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        log.info("\(String(describing: central.state.rawValue))")
    }

    func bleCentralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        if peripheral.name == nil || deviceNameRegex.firstMatch(
            in: peripheral.name!,
            range: NSMakeRange(0, peripheral.name!.count)
        ) == nil {
            return
        }

        dispatchPrecondition(condition: .onQueue(managerQueue))
        log.info("\(peripheral), \(advertisementData)")

        if autoConnectUUID != nil, peripheral.identifier.uuidString == autoConnectUUID {
            stopScan()
            connect(peripheral, connectionCompletion!)
            return
        }

        let device: DanaPumpScan? = devices.first(where: { $0.bleIdentifier == peripheral.identifier.uuidString })
        if device != nil {
            return
        }

        let result = DanaPumpScan(bleIdentifier: peripheral.identifier.uuidString, name: peripheral.name!, peripheral: peripheral)
        devices.append(result)
        pumpManagerDelegate?.notifyScanDeviceDidChange(result)
    }

    func bleCentralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        guard let connectionCompletion = self.connectionCompletion else {
            log.error("No connection callback found... Timeout hit probably")
            disconnect(peripheral, force: false)

            return
        }

        log.info("Connected to pump!")
        self.peripheral = peripheral
        peripheralManager = PeripheralManager(peripheral, self, pumpManagerDelegate!, connectionCompletion)

        pumpManagerDelegate?.state.deviceName = peripheral.name
        pumpManagerDelegate?.state.bleIdentifier = peripheral.identifier.uuidString
        pumpManagerDelegate?.notifyStateDidChange()

        peripheral.discoverServices([PeripheralManager.SERVICE_UUID])
    }

    func bleCentralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            log.error("Failed to disconnect: \(error.localizedDescription)")
            logDeviceCommunication("Dana - FAILED TO DISCONNECT: \(error.localizedDescription)", type: .connection)
        } else {
            logDeviceCommunication("Dana - Disconnected", type: .connection)
            log.info("Device disconnected, name: \(peripheral.name ?? "<NO_NAME>")")
        }

        pumpManagerDelegate?.state.isConnected = false
        pumpManagerDelegate?.notifyStateDidChange()

        self.peripheral = nil
        peripheralManager = nil

        pumpManagerDelegate?.checkBolusDone()
    }

    func bleCentralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.info("Device connect error, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error!.localizedDescription)")
    }
}
