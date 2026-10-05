import CoreBluetooth
import Foundation
import MedtrumSimulatorProtocol

@MainActor
final class SimulatorModel: NSObject, ObservableObject {
    enum Identity: String, CaseIterable, Identifiable {
        case nano200 = "Medtrum Pump Simulator 200U"
        case nano300 = "Medtrum Pump Simulator 300U"

        var id: String { rawValue }
        var serial: String { self == .nano200 ? "4A12D828" : "52DF1614" }
        var reservoirCapacity: Double { self == .nano200 ? 200 : 300 }
    }

    @Published var isAdvertising = false
    @Published var bluetoothState = "Initializing"
    @Published var subscribers = 0
    @Published var identity: Identity = .nano200
    @Published var reservoir = 200.0
    @Published var battery = 2.80
    @Published var basalRate = 1.0
    @Published var bolusDescription = "None"
    @Published var patchState = "Idle"
    @Published var selectedAlarm: AlarmInjection = .none
    @Published var logEntries: [String] = []

    private let engine = MedtrumProtocolEngine()
    private var peripheralManager: CBPeripheralManager!
    private var readCharacteristic: CBMutableCharacteristic?
    private var writeCharacteristic: CBMutableCharacteristic?
    private var assembler = MedtrumRequestAssembler()
    private var pendingUpdates: [(Data, CBMutableCharacteristic)] = []
    private var timer: Timer?

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        appendLog("TRAINING SIMULATOR initialized; no central-mode code exists")
        refreshPublishedState()
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard peripheralManager.state == .poweredOn else {
            appendLog("Cannot start: Bluetooth is \(bluetoothState)")
            return
        }
        installServiceIfNeeded()
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "MT-SIM",
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: MedtrumUUID.service)]
        ])
        appendLog("Starting peripheral advertisement as MT-SIM")
    }

    func stop() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        appendLog("Advertisement stopped")
    }

    func reset() {
        engine.reset()
        engine.setReservoir(identity.reservoirCapacity)
        engine.setBattery(battery)
        assembler.reset()
        pendingUpdates.removeAll()
        selectedAlarm = .none
        appendLog("Simulation state reset")
        refreshPublishedState()
        notifyState()
    }

    func identityChanged() {
        engine.setReservoir(identity.reservoirCapacity)
        reservoir = identity.reservoirCapacity
        appendLog("Identity selected: \(identity.rawValue), serial \(identity.serial)")
        notifyState()
    }

    func controlsChanged() {
        engine.setReservoir(reservoir)
        engine.setBattery(battery)
        engine.setBasalRate(basalRate)
        refreshPublishedState()
        notifyState()
    }

    func injectAlarm() {
        engine.inject(selectedAlarm)
        appendLog("Injected training condition: \(selectedAlarm.rawValue)")
        refreshPublishedState()
        notifyState()
    }

    private func installServiceIfNeeded() {
        guard readCharacteristic == nil, writeCharacteristic == nil else { return }

        let read = CBMutableCharacteristic(
            type: CBUUID(string: MedtrumUUID.read),
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        let write = CBMutableCharacteristic(
            type: CBUUID(string: MedtrumUUID.write),
            properties: [.write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: CBUUID(string: MedtrumUUID.service), primary: true)
        service.characteristics = [read, write]
        readCharacteristic = read
        writeCharacteristic = write
        peripheralManager.add(service)
    }

    private func tick() {
        if engine.advance() {
            refreshPublishedState()
            notifyState()
        }
    }

    private func handle(_ request: MedtrumRequest, central: CBCentral?) {
        let outcome = engine.handle(request)
        appendLog("RX 0x\(hex(request.command)) seq \(request.sequence): \(outcome.event)")

        let mtu = central?.maximumUpdateValueLength ?? 20
        for frame in MedtrumResponseEncoder.encode(outcome.response, maximumUpdateLength: mtu) {
            enqueue(frame, on: writeCharacteristic)
        }
        refreshPublishedState()
        if outcome.shouldNotifyState {
            notifyState()
        }
    }

    private func notifyState() {
        guard engine.state.subscribed else { return }
        enqueue(engine.heartbeatValue(), on: readCharacteristic)
    }

    private func enqueue(_ data: Data, on characteristic: CBMutableCharacteristic?) {
        guard let characteristic else { return }
        if pendingUpdates.isEmpty,
           peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
        {
            return
        }
        pendingUpdates.append((data, characteristic))
        flushUpdates()
    }

    private func flushUpdates() {
        while let next = pendingUpdates.first {
            guard peripheralManager.updateValue(next.0, for: next.1, onSubscribedCentrals: nil) else {
                return
            }
            pendingUpdates.removeFirst()
        }
    }

    private func refreshPublishedState() {
        let state = engine.state
        reservoir = state.reservoir
        battery = state.batteryVoltage
        basalRate = state.basalRate
        patchState = state.patchState.title
        if let requested = state.bolusRequested {
            bolusDescription = String(format: "%.2f / %.2f U", state.bolusDelivered, requested)
        } else {
            bolusDescription = "None"
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        logEntries.insert("\(timestamp)  \(message)", at: 0)
        if logEntries.count > 300 {
            logEntries.removeLast(logEntries.count - 300)
        }
    }

    private func hex(_ value: UInt8) -> String {
        String(format: "%02X", value)
    }
}

extension SimulatorModel: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            switch peripheral.state {
            case .poweredOn: bluetoothState = "Powered on"
            case .poweredOff: bluetoothState = "Powered off"
            case .unauthorized: bluetoothState = "Unauthorized"
            case .unsupported: bluetoothState = "Unsupported"
            case .resetting: bluetoothState = "Resetting"
            case .unknown: bluetoothState = "Unknown"
            @unknown default: bluetoothState = "Unknown"
            }
            appendLog("Bluetooth state: \(bluetoothState)")
            if peripheral.state != .poweredOn {
                isAdvertising = false
            }
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            isAdvertising = error == nil
            appendLog(error.map { "Advertising failed: \($0.localizedDescription)" } ?? "Advertising started")
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            appendLog(error.map { "GATT service failed: \($0.localizedDescription)" } ?? "Medtrum GATT service published")
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            subscribers += 1
            appendLog("iPhone subscribed to \(characteristic.uuid.uuidString); MTU \(central.maximumUpdateValueLength)")
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            subscribers = max(0, subscribers - 1)
            appendLog("Central unsubscribed from \(characteristic.uuid.uuidString)")
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        Task { @MainActor in
            let value = engine.heartbeatValue()
            guard request.offset <= value.count else {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            request.value = Data(value.dropFirst(request.offset))
            peripheral.respond(to: request, withResult: .success)
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        Task { @MainActor in
            for request in requests {
                guard request.characteristic.uuid == CBUUID(string: MedtrumUUID.write),
                      let value = request.value,
                      request.offset == 0
                else {
                    peripheral.respond(to: request, withResult: .requestNotSupported)
                    continue
                }
                do {
                    let complete = try assembler.append(value)
                    peripheral.respond(to: request, withResult: .success)
                    if let complete {
                        handle(complete, central: request.central)
                    }
                } catch {
                    assembler.reset()
                    appendLog("Rejected malformed frame: \(error)")
                    peripheral.respond(to: request, withResult: .unlikelyError)
                }
            }
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Task { @MainActor in flushUpdates() }
    }
}
