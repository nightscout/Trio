import BackgroundTasks
import CoreBluetooth
import Foundation
import UserNotifications

class ContinousBluetoothManager: NSObject, BluetoothManager {
    var pumpManagerDelegate: DanaKitPumpManager? {
        didSet {
            autoConnectUUID = pumpManagerDelegate?.state.bleIdentifier
        }
    }

    var autoConnectUUID: String?
    var connectionCompletion: ((ConnectionResult) -> Void)?
    var connectionCallback: [String: (ConnectionResult) -> Void] = [:]
    var devices: [DanaPumpScan] = []

    let log = DanaLogger(category: "ContinousBluetoothManager")
    var manager: CBCentralManager!
    let managerQueue = DispatchQueue(label: "com.DanaKit.bluetoothManagerQueue", qos: .unspecified)

    var peripheral: CBPeripheral?
    var peripheralManager: PeripheralManager?
    var forcedDisconnect = false

    public var isConnected: Bool {
        self.manager.state == .poweredOn && self.peripheral?.state == .connected && self.pumpManagerDelegate?.state
            .isConnected ?? false
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

    private func handleBackgroundTask() {
        Task {
            while isConnected {
                await keepConnectionAlive()
                try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            }

            self.log.warning("Existed background job. Not connected anymore")
        }
    }

    private func keepConnectionAlive() async {
        do {
            if pumpManagerDelegate?.status.bolusState == .noBolus {
                log.info("Sending keep alive message")
                let keepAlivePacket = generatePacketGeneralKeepConnection()
                let result = try await writeMessage(keepAlivePacket)
                guard result.success else {
                    log.error("Pump rejected keepAlive request: \(result.rawData.base64EncodedString())")
                    return
                }
            } else {
                log.info("Skip sending keep alive message. Reason: bolus is running")
            }
        } catch {
            log.error("Failed to keep connection alive: \(error.localizedDescription)")
        }
    }

    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol) {
        guard let peripheralManager = self.peripheralManager, isConnected else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }

        return try await peripheralManager.writeMessage(packet)
    }

    public func reconnect(_ callback: @escaping (Bool) -> Void) {
        guard !isConnected else {
            callback(true)
            return
        }

        NotificationHelper.setDisconnectWarning()
        if autoConnectUUID == nil {
            autoConnectUUID = pumpManagerDelegate?.state.bleIdentifier
        }

        if peripheral != nil {
            connect(peripheral!) { result in
                switch result {
                case .success:
                    self.forcedDisconnect = false
                    Task {
                        await self.updateInitialState()
                        self.handleBackgroundTask()
                        callback(true)
                    }
                default:
                    self.log.error("Failed to reconnect: \(result)")
                    callback(false)
                }
            }
            return
        }

        guard let autoConnect = autoConnectUUID else {
            log.error("No autoConnect: \(String(describing: autoConnectUUID))")
            callback(false)
            return
        }

        do {
            try connect(autoConnect) { result in
                switch result {
                case .success:
                    self.forcedDisconnect = false
                    Task {
                        await self.updateInitialState()
                        self.handleBackgroundTask()
                        callback(true)
                    }
                default:
                    self.log.error("Failed to do auto connection: \(result)")
                    callback(false)
                }
            }
        } catch {
            log.error("Failed to auto connect: \(error.localizedDescription)")
            callback(false)
        }
    }

    func ensureConnected(_ completion: @escaping (ConnectionResult) async -> Void, _: String = #function) {
        if isConnected {
            resetConnectionCompletion()
            logDeviceCommunication("Dana - Connection is ok!", type: .connection)
            Task {
                await self.updateInitialState()
                await completion(.success)
            }

        } else if !forcedDisconnect {
            reconnect { result in
                guard result else {
                    self.log.error("Failed to reconnect")
                    self.logDeviceCommunication("Dana - Couldn't reconnect", type: .connection)

                    self.resetConnectionCompletion()
                    Task {
                        await completion(.failure(NSError(domain: "Couldn't reconnect", code: -1)))
                    }
                    return
                }

                self.resetConnectionCompletion()
                self.logDeviceCommunication("Dana - Reconnected!", type: .connection)
                Task {
                    await self.updateInitialState()
                    await completion(.success)
                }
            }
        } else {
            // We aren't connected, the user has disconnected the pump by hand
            log.warning("Device is forced disconnected...")
            logDeviceCommunication(
                "Dana - Pump is not connected. Please reconnect to pump before doing any operations",
                type: .connection
            )

            resetConnectionCompletion()
            Task {
                await completion(.failure(NSError(domain: "Device is forced disconnected...", code: -1)))
            }
        }
    }

    func disconnect(_ peripheral: CBPeripheral, force: Bool) {
        guard force else {
            return
        }

        autoConnectUUID = nil
        forcedDisconnect = true

        logDeviceCommunication("Dana - Disconnected", type: .connection)
        manager.cancelPeripheralConnection(peripheral)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bleCentralManagerDidUpdateState(central)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if central.state == .poweredOn {
                self.reconnect { result in
                    guard result else {
                        return
                    }

                    self.log.info("Reconnected and sync pump data!")
                    self.pumpManagerDelegate?.syncPump { _ in }
                }
            }
        }
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

        NotificationHelper.clearDisconnectWarning()
        NotificationHelper.clearDisconnectReminder()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        bleCentralManager(central, didDisconnectPeripheral: peripheral, error: error)

        guard !forcedDisconnect else {
            // Dont reconnect if the user has manually disconnected
            return
        }

        reconnect { result in
            guard result else {
                return
            }

            self.log.info("Reconnected and sync pump data!")
            self.pumpManagerDelegate?.syncPump { _ in }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        bleCentralManager(central, didFailToConnect: peripheral, error: error)
    }
}
