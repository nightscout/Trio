import Combine
import CoreBluetooth
import Foundation
import Libre2Protocol

enum AlarmScenario: String, CaseIterable, Identifiable {
    case none = "None"
    case low = "Low (55)"
    case high = "High (300)"

    var id: String { rawValue }
}

// CoreBluetooth and the timer are both deliberately scheduled on the main
// queue; this satisfies the synchronization promise behind unchecked Sendable.
final class SimulatorModel: NSObject, ObservableObject, @unchecked Sendable {
    @Published var bluetoothState = "Initializing"
    @Published var isAdvertising = false
    @Published var wantsAdvertising = false
    @Published var subscriberCount = 0
    @Published var isUnlocked = false
    @Published var glucose = 110.0
    @Published var trend = Libre2Trend.stable
    @Published var automaticCurve = false
    @Published var curveAmplitude = 35.0
    @Published var alarmScenario = AlarmScenario.none
    @Published var dropoutEvery = 0
    @Published var intervalSeconds = 60.0
    @Published var sensorAgeMinutes = 90
    @Published var logs: [String] = []

    let serial = Libre2Profile.serial
    let localName = Libre2Profile.localName
    let sensorUIDHex = Libre2Profile.sensorUID.map { String(format: "%02X", $0) }.joined()

    private var peripheralManager: CBPeripheralManager!
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var timer: Timer?
    private var pendingChunks: [Data] = []
    private var maximumChunkLength = 20
    private var transmissionCount = 0
    private var curvePhase = 0.0

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        appendLog("Simulator initialized; no central/scanner APIs are used")
    }

    func start() {
        wantsAdvertising = true
        configureServiceIfPossible()
        restartTimer()
    }

    func stop() {
        wantsAdvertising = false
        peripheralManager.stopAdvertising()
        isAdvertising = false
        timer?.invalidate()
        timer = nil
        appendLog("Advertising stopped")
    }

    func reset() {
        stop()
        glucose = 110
        trend = .stable
        automaticCurve = false
        curveAmplitude = 35
        alarmScenario = .none
        dropoutEvery = 0
        intervalSeconds = 60
        sensorAgeMinutes = 90
        transmissionCount = 0
        curvePhase = 0
        isUnlocked = false
        pendingChunks.removeAll()
        logs = []
        appendLog("Reset complete")
    }

    func sendNow() {
        guard subscriberCount > 0 else {
            appendLog("Send skipped: no subscribed iPhone")
            return
        }
        guard isUnlocked else {
            appendLog("Send skipped: waiting for stock MiaoMiao F0 request")
            return
        }
        transmissionCount += 1
        if dropoutEvery > 0, transmissionCount.isMultiple(of: dropoutEvery) {
            appendLog("Intentional dropout #\(transmissionCount)")
            return
        }

        let outputGlucose: Double
        switch alarmScenario {
        case .none: outputGlucose = glucose
        case .low: outputGlucose = 55
        case .high: outputGlucose = 300
        }

        if automaticCurve {
            curvePhase += 0.22
            glucose = min(350, max(40, 120 + sin(curvePhase) * curveAmplitude))
        }

        do {
            let packet = try Libre2Codec.makeMiaoMiaoPacket(
                glucoseMGDL: outputGlucose,
                trend: trend,
                ageMinutes: sensorAgeMinutes
            )
            sensorAgeMinutes = min(65_535, sensorAgeMinutes + max(1, Int(intervalSeconds / 60)))
            pendingChunks += packet.chunked(maximumLength: maximumChunkLength)
            appendLog("Queued 363-byte MiaoMiao packet: \(Int(outputGlucose)) mg/dL, \(trend.rawValue), age \(sensorAgeMinutes)m")
            flushNotifications()
        } catch {
            appendLog("Packet generation failed: \(error)")
        }
    }

    func restartTimer() {
        timer?.invalidate()
        guard wantsAdvertising else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(1, intervalSeconds), repeats: true) { [weak self] _ in
            self?.sendNow()
        }
    }

    private func configureServiceIfPossible() {
        guard wantsAdvertising, peripheralManager.state == .poweredOn else { return }
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()

        let write = CBMutableCharacteristic(
            type: CBUUID(string: Libre2Profile.writeUUID),
            properties: [.write, .writeWithoutResponse, .read],
            value: nil,
            permissions: [.writeable, .readable]
        )
        let notify = CBMutableCharacteristic(
            type: CBUUID(string: Libre2Profile.notifyUUID),
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        notifyCharacteristic = notify
        let service = CBMutableService(type: CBUUID(string: Libre2Profile.serviceUUID), primary: true)
        service.characteristics = [write, notify]
        peripheralManager.add(service)
        appendLog("Adding stock MiaoMiao Nordic UART service")
    }

    private func beginAdvertising() {
        guard wantsAdvertising else { return }
        // CBPeripheralManager supports local name and service UUIDs in peripheral
        // mode. It does not expose manufacturer-data advertising on macOS.
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: Libre2Profile.localName,
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Libre2Profile.serviceUUID)]
        ])
    }

    private func flushNotifications() {
        guard let notifyCharacteristic else { return }
        while let chunk = pendingChunks.first {
            if peripheralManager.updateValue(chunk, for: notifyCharacteristic, onSubscribedCentrals: nil) {
                pendingChunks.removeFirst()
                appendLog("Notified Nordic UART RX with \(chunk.count) bytes")
            } else {
                appendLog("Notification flow-controlled; waiting for ready callback")
                return
            }
        }
    }

    private func appendLog(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append("\(formatter.string(from: Date()))  \(text)")
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }
}

extension SimulatorModel: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn: bluetoothState = "Powered on"
        case .poweredOff: bluetoothState = "Powered off"
        case .unauthorized: bluetoothState = "Unauthorized"
        case .unsupported: bluetoothState = "Unsupported"
        case .resetting: bluetoothState = "Resetting"
        case .unknown: bluetoothState = "Unknown"
        @unknown default: bluetoothState = "Future state"
        }
        appendLog("Bluetooth state: \(bluetoothState)")
        configureServiceIfPossible()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            appendLog("Failed adding \(service.uuid): \(error.localizedDescription)")
            return
        }
        appendLog("GATT service \(service.uuid) ready")
        beginAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            isAdvertising = false
            appendLog("Advertising failed: \(error.localizedDescription)")
        } else {
            isAdvertising = true
            appendLog("Advertising \(localName), stock MiaoMiao service")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscriberCount += 1
        maximumChunkLength = max(1, min(20, central.maximumUpdateValueLength))
        appendLog("Central \(central.identifier.uuidString) subscribed to \(characteristic.uuid)")
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscriberCount = max(0, subscriberCount - 1)
        appendLog("Central \(central.identifier.uuidString) unsubscribed")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == CBUUID(string: Libre2Profile.writeUUID),
                  let value = request.value else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }
            peripheral.respond(to: request, withResult: .success)
            if value == Data([0xF0]) {
                isUnlocked = true
                appendLog("Accepted stock MiaoMiao F0 data request")
                sendNow()
            } else if value == Data([0xD3, 0x01]) {
                appendLog("Accepted stock MiaoMiao sensor confirmation")
            } else {
                appendLog("Accepted MiaoMiao control write: \(value.map { String(format: "%02X", $0) }.joined())")
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == CBUUID(string: Libre2Profile.writeUUID) {
            request.value = Data()
            peripheral.respond(to: request, withResult: .success)
        } else if request.characteristic.uuid == CBUUID(string: Libre2Profile.notifyUUID) {
            request.value = Data()
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        appendLog("Notification queue ready")
        flushNotifications()
    }
}

private extension Data {
    func chunked(maximumLength: Int) -> [Data] {
        stride(from: 0, to: count, by: maximumLength).map {
            subdata(in: $0..<Swift.min($0 + maximumLength, count))
        }
    }
}
