import CoreBluetooth
import LoopKit
import SwiftUI

struct ScanResultItem: Identifiable {
    let id = UUID()
    var name: String
    let bleIdentifier: String
}

class DanaKitScanViewModel: ObservableObject {
    @Published var scannedDevices: [ScanResultItem] = []
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var connectingTo: String? = nil
    @Published var isPromptingPincode = false
    @Published var pinCodePromptError: String?
    @Published var isConnectionError = false
    @Published var connectionErrorMessage: String?

    @Published var pin1 = ""
    @Published var pin2 = ""

    private let log = DanaLogger(category: "ScanView")
    private var pumpManager: DanaKitPumpManager?
    private var nextStep: () -> Void
    private var foundDevices: [String: CBPeripheral] = [:]

    init(_ pumpManager: DanaKitPumpManager? = nil, nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep

        self.pumpManager?.addScanDeviceObserver(self, queue: .main)
        self.pumpManager?.addStateObserver(self, queue: .main)

        do {
            try self.pumpManager?.startScan()
            isScanning = true
        } catch {
            log.error("Failed to start scanning: \(error.localizedDescription)")
        }
    }

    func connect(_ item: ScanResultItem) {
        guard let device = foundDevices[item.bleIdentifier] else {
            log.error("No view or device...")
            return
        }

        stopScan()
        connectingTo = item.name

        pumpManager?.connect(device) { result in
            DispatchQueue.main.async {
                self.connectComplete(result, device)
            }
        }
        isConnecting = true
    }

    func connectComplete(_ result: ConnectionResult, _ peripheral: CBPeripheral) {
        switch result {
        case .success:
            syncTime(peripheral)

        case let .failure(e):
            isConnecting = false
            isConnectionError = true
            connectionErrorMessage = e.localizedDescription

        case .invalidBle5Keys:
            isConnecting = false
            isConnectionError = true
            connectionErrorMessage = LocalizedString("Failed to pair to ", comment: "Dana-i failed to pair p1") +
                (pumpManager?.state.deviceName ?? "<NO_NAME>") + LocalizedString(
                    ". Please go to your bluetooth settings, forget this device, and try again",
                    comment: "Dana-i failed to pair p2"
                )

        case let .requestedPincode(message):
            isConnecting = true
            isPromptingPincode = true
            pinCodePromptError = message
        case .timeout:
            isConnecting = false
            isConnectionError = true
            connectionErrorMessage = "Connection timeout is hit..."
        case .alreadyConnectedAndBusy:
            isConnecting = false
            isConnectionError = true
            connectionErrorMessage = "Device is already connected..."
        }
    }

    func stopScan() {
        pumpManager?.stopScan()
        isScanning = false
    }

    func cancelPinPrompt() {
        isPromptingPincode = false
        pumpManager?.disconnect()
    }

    func syncTime(_ peripheral: CBPeripheral) {
        pumpManager?.syncPumpTime { error in
            if let error = error {
                self.log.error("Failed to sync pump time: \(error)")
            }

            self.pumpManager?.disconnect(peripheral)
            DispatchQueue.main.async {
                self.nextStep()
            }
        }
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
}

extension DanaKitScanViewModel: StateObserver {
    func deviceScanDidUpdate(_ device: DanaPumpScan) {
        scannedDevices.append(ScanResultItem(name: device.name, bleIdentifier: device.bleIdentifier))
        foundDevices[device.bleIdentifier] = device.peripheral
    }

    func stateDidUpdate(_: DanaKitPumpManagerState, _: DanaKitPumpManagerState) {
        // Not needed
    }
}
