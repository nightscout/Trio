import LoopKit
import SwiftUI

class DanaKitDebugViewModel: ObservableObject {
    @Published var scannedDevices: [DanaPumpScan] = []

    @Published var isPresentingTempBasalAlert = false
    @Published var isPresentingScanAlert = false
    @Published var isPresentingBolusAlert = false
    @Published var isPresentingScanningErrorAlert = false
    @Published var isPromptingPincode = false
    @Published var pinCodePromptError: String?
    @Published var scanningErrorMessage = ""
    @Published var connectedDeviceName = ""
    @Published var messageScanAlert = ""
    @Published var isConnected = false
    @Published var isConnectionError = false
    @Published var connectionErrorMessage: String?

    @Published var pin1 = ""
    @Published var pin2 = ""

    private let log = DanaLogger(category: "DebugView")
    private var pumpManager: DanaKitPumpManager?
    private var connectedDevice: DanaPumpScan?

    init(_ pumpManager: DanaKitPumpManager? = nil) {
        self.pumpManager = pumpManager

        self.pumpManager?.addScanDeviceObserver(self, queue: .main)
        self.pumpManager?.addStateObserver(self, queue: .main)
    }

    func scan() {
        do {
            try pumpManager?.startScan()
        } catch {
            isPresentingScanningErrorAlert = true
            scanningErrorMessage = error.localizedDescription
        }
    }

    func connect() {
        guard let device = scannedDevices.last else {
            log.error("No view or device...")
            return
        }

        pumpManager?.stopScan()
        pumpManager?.connect(device.peripheral, connectCompletion)
        connectedDevice = device
    }

    func connectCompletion(_ result: ConnectionResult) {
        switch result {
        case .success:
            isConnected = true

        case let .failure(error):
            isConnectionError = true
            connectionErrorMessage = error.localizedDescription

        case .invalidBle5Keys:
            isConnectionError = true
            connectionErrorMessage = LocalizedString("Failed to pair to ", comment: "Dana-i failed to pair p1") +
                (pumpManager?.state.deviceName ?? "<NO_NAME>") + LocalizedString(
                    ". Please go to your bluetooth settings, forget this device, and try again",
                    comment: "Dana-i failed to pair p2"
                )

        case let .requestedPincode(message):
            isPromptingPincode = true
            pinCodePromptError = message

        case .timeout:
            isConnectionError = true
            connectionErrorMessage = "Connection timeout is hit..."

        case .alreadyConnectedAndBusy:
            isConnectionError = true
            connectionErrorMessage = "Device is already connected..."
        }
    }

    func cancelPinPrompt() {
        isPromptingPincode = false
        pumpManager?.disconnect()
    }

    func processPinPrompt() {
        guard pin1.count == 12, pin2.count == 8 else {
            pinCodePromptError = LocalizedString(
                "Received invalid pincode lengths. Try again",
                comment: "Dana-RS v3 pincode prompt error invalid length"
            )
            isPromptingPincode = true
            return
        }

        guard let pin1 = Data(hexString: pin1), let pin2 = Data(hexString: pin2) else {
            pinCodePromptError = LocalizedString(
                "Received invalid hex strings. Try again",
                comment: "Dana-RS v3 pincode prompt error invalid hex"
            )
            isPromptingPincode = true
            return
        }

        let randomPairingKey = pin2.prefix(3)
        let checkSum = pin2.dropFirst(3).prefix(1)

        var pairingKeyCheckSum: UInt8 = 0
        for byte in pin1 {
            pairingKeyCheckSum ^= byte
        }

        for byte in randomPairingKey {
            pairingKeyCheckSum ^= byte
        }

        guard checkSum.first == pairingKeyCheckSum else {
            pinCodePromptError = LocalizedString(
                "Checksum failed. Try again",
                comment: "Dana-RS v3 pincode prompt error checksum failed"
            )
            isPromptingPincode = true
            return
        }

        do {
            try pumpManager?.finishV3Pairing(pin1, randomPairingKey)
        } catch {}
    }

    func bolusModal() {
        isPresentingBolusAlert = true
    }

    func bolus() {
        pumpManager?.enactBolus(units: 5.0, activationType: .manualNoRecommendation, completion: bolusCompletion)
        isPresentingBolusAlert = false
    }

    func bolusCompletion(_ error: PumpManagerError?) {
        if error == nil {
            return
        }

        log.error("Bolus failed...")
    }

    func stopBolus() {
        pumpManager?.cancelBolus(completion: bolusCancelCompletion)
    }

    func bolusCancelCompletion(_ result: PumpManagerResult<DoseEntry?>) {
        if case .success = result {
            return
        } else {
            log.error("Cancel failed...")
        }
    }

    func tempBasalModal() {
        isPresentingTempBasalAlert = true
    }

    func tempBasal() {
        // 200% temp basal for 2 hours
        pumpManager?.enactTempBasal(unitsPerHour: 1, for: 7200, completion: tempBasalCompletion)
        isPresentingTempBasalAlert = false
    }

    func tempBasalCompletion(_ error: PumpManagerError?) {
        if error == nil {
            return
        }

        log.error("Temp basal failed...")
    }

    func stopTempBasal() {
        pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0, completion: tempBasalCompletion)
    }

    func basal() {
        let basal = Array(0 ..< 24).map({ RepeatingScheduleValue<Double>(startTime: TimeInterval(60 * 30 * $0), value: 0.5) })
        pumpManager?.syncBasalRateSchedule(items: basal, completion: basalCompletion)
    }

    func basalCompletion(_ result: Result<DailyValueSchedule<Double>, any Error>) {
        if case .success = result {
            return
        } else {
            log.error("Cancel failed...")
        }
    }

    func disconnect() {
        guard let device = connectedDevice else {
            return
        }

        pumpManager?.disconnect(device.peripheral)
    }

    func getLogs() -> [URL] {
        log.getDebugLogs()
    }
}

extension DanaKitDebugViewModel: StateObserver {
    func deviceScanDidUpdate(_ device: DanaPumpScan) {
        log.info("Found device \(device.name)")
        scannedDevices.append(device)

        messageScanAlert = "Do you want to connect to: " + device.name + " (" + device.bleIdentifier + ")"
        isPresentingScanAlert = true
    }

    func stateDidUpdate(_ state: DanaKitPumpManagerState, _: DanaKitPumpManagerState) {
        isConnected = state.isConnected
        connectedDeviceName = state.deviceName ?? ""
    }
}
