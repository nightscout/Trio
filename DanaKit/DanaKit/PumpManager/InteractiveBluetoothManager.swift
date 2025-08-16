import CoreBluetooth
import Foundation
import LoopKit

class InteractiveBluetoothManager: NSObject, BluetoothManager {
    weak var pumpManagerDelegate: DanaKitPumpManager?

    var autoConnectUUID: String?
    var connectionCompletion: ((ConnectionResult) -> Void)?
    var connectionCallback: [String: (ConnectionResult) -> Void] = [:]
    var devices: [DanaPumpScan] = []
    var isBusy: Bool = false

    let log = DanaLogger(category: "InteractiveBluetoothManager")
    var manager: CBCentralManager!
    let managerQueue = DispatchQueue(label: "com.DanaKit.bluetoothManagerQueue", qos: .unspecified)

    var peripheral: CBPeripheral?
    var peripheralManager: PeripheralManager?

    public var isConnected: Bool {
        self.manager.state == .poweredOn && self.peripheral?.state == .connected
    }

    override init() {
        super.init()

        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue)
        }
    }

    deinit {
        self.manager = nil
    }

    func ensureConnected(_ completion: @escaping (ConnectionResult) async -> Void, _ identifier: String = #function) {
        connectionCallback[identifier] = { result in
            Task {
                self.isBusy = true
                self.resetConnectionCompletion()
                self.connectionCallback[identifier] = nil

                if case .success = result {
                    do {
                        self.log.info("Sending keep alive message")

                        let keepAlivePacket = generatePacketGeneralKeepConnection()
                        _ = try await self.writeMessage(keepAlivePacket)
                    } catch {
                        self.log.error("Failed to send Keep alive message: \(error.localizedDescription)")
                    }

                    await self.updateInitialState()
                }

                await completion(result)
                self.isBusy = false
            }
        }

        // Device still has an active connection with pump and is probably busy with something
        if isConnected {
            if isBusy {
                log.error("Failed to connect: Already connected")
                logDeviceCommunication("Dana - Failed to connect: Already connected", type: .connection)
                connectionCallback[identifier]!(.alreadyConnectedAndBusy)
                return
            }

            // We can re-use the current connection. YEAH!!
            connectionCallback[identifier]!(.success)

            // We stored the peripheral. We can quickly reconnect
        } else if peripheral != nil {
            startTimeout(seconds: TimeInterval.seconds(15), identifier)

            connect(peripheral!) { result in
                guard let connectionCallback = self.connectionCallback[identifier] else {
                    // We've already hit the timeout function above
                    // Exit if we every hit this...
                    return
                }

                if case .success = result {
                    self.logDeviceCommunication("Dana - Connected", type: .connection)
                    connectionCallback(result)

                } else if case let .failure(err) = result {
                    self.log.error("Failed to connect: " + err.localizedDescription)
                    self.logDeviceCommunication("Dana - Failed to connect: " + err.localizedDescription, type: .connection)
                    connectionCallback(result)

                } else if case .requestedPincode = result {
                    self.log.error("Failed to connect: Requested pincode")
                    self.logDeviceCommunication("Dana - Requested pincode", type: .connection)
                    connectionCallback(result)

                } else if case .invalidBle5Keys = result {
                    self.log.error("Failed to connect: Invalid ble 5 keys")
                    self.logDeviceCommunication("Dana - Invalid ble 5 keys", type: .connection)
                    connectionCallback(result)
                }
            }
            // No active connection and no stored peripheral. We have to scan for device before being able to send command
        } else if pumpManagerDelegate?.state.bleIdentifier != nil {
            do {
                startTimeout(seconds: TimeInterval.seconds(30), identifier)

                try connect(pumpManagerDelegate!.state.bleIdentifier!) { result in
                    guard let connectionCallback = self.connectionCallback[identifier] else {
                        // We've already hit the timeout function above
                        // Exit if we every hit this...
                        return
                    }

                    if case .success = result {
                        self.logDeviceCommunication("Dana - Connected", type: .connection)
                        connectionCallback(result)

                    } else if case let .failure(err) = result {
                        self.log.error("Failed to connect: " + err.localizedDescription)
                        self.logDeviceCommunication("Dana - Failed to connect: " + err.localizedDescription, type: .connection)
                        connectionCallback(result)

                    } else if case .requestedPincode = result {
                        self.log.error("Failed to connect: Requested pincode")
                        self.logDeviceCommunication("Dana - Requested pincode", type: .connection)
                        connectionCallback(result)

                    } else if case .invalidBle5Keys = result {
                        self.log.error("Failed to connect: Invalid ble 5 keys")
                        self.logDeviceCommunication("Dana - Invalid ble 5 keys", type: .connection)
                        connectionCallback(result)
                    }
                }
            } catch {
                log.error("Failed to connect: " + error.localizedDescription)
                logDeviceCommunication("Dana - Failed to connect: " + error.localizedDescription, type: .connection)
                connectionCallback[identifier]?(.failure(error))
            }

        } else {
            // Should never reach, but is only possible if device is not onboard (we have no ble identifier to connect to)
            log.error("Pump is not onboarded")
            logDeviceCommunication("Dana - Pump is not onboarded", type: .connection)
            connectionCallback[identifier]!(.failure(NSError(domain: "Pump is not onboarded", code: -1)))
        }
    }

    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol) {
        guard let peripheralManager = self.peripheralManager else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }

        return try await peripheralManager.writeMessage(packet)
    }

    func disconnect(_ peripheral: CBPeripheral, force _: Bool) {
        autoConnectUUID = nil

        logDeviceCommunication("Dana - Disconnected", type: .connection)
        manager.cancelPeripheralConnection(peripheral)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bleCentralManagerDidUpdateState(central)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        bleCentralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        bleCentralManager(central, didConnect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isBusy = false
        bleCentralManager(central, didDisconnectPeripheral: peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        bleCentralManager(central, didFailToConnect: peripheral, error: error)
    }
}
