import LoopKit
import LoopKitUI
import MockKit
import SwiftDate
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var setupPump = false
        private(set) var setupPumpType: PumpType = .minimed
        @Published var pumpState: PumpDisplayState?
        private(set) var initialSettings: PumpInitialSettings = .default
        @Published var alertNotAck: Bool = false
        @Injected() var bluetoothManager: BluetoothStateManager!

        override func subscribe() {
            provider.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpState, on: self)
                .store(in: &lifetime)

            // Check if pump simulator is selected and should be hidden
            checkAndResetPumpSimulatorIfNeeded()

            alertNotAck = provider.initialAlertNotAck()
            provider.alertNotAck
                .receive(on: DispatchQueue.main)
                .assign(to: \.alertNotAck, on: self)
                .store(in: &lifetime)

            Task {
                let basalSchedule = BasalRateSchedule(
                    dailyItems: await provider.getBasalProfile().map {
                        RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                    }
                )

                let pumpSettings = provider.pumpSettings()

                await MainActor.run {
                    initialSettings = PumpInitialSettings(
                        maxBolusUnits: Double(pumpSettings.maxBolus),
                        maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                        basalSchedule: basalSchedule!
                    )
                }
            }
        }

        func addPump(_ type: PumpType) {
            setupPumpType = type
            setupPump = true
        }

        func ack() {
            provider.deviceManager.alertHistoryStorage.forceNotification()
        }

        /// Checks if the pump simulator is selected and resets it if Bundle.main.simulatorVisibility.isHidden is true
        private func checkAndResetPumpSimulatorIfNeeded() {
            // Only proceed if simulators should be hidden
            guard Bundle.main.simulatorVisibility.isHidden else { return }

            // Check if the current pump is a simulator
            if provider.apsManager.pumpManager is MockPumpManager {
                // Reset the pump manager to nil to allow selecting a new pump
                provider.apsManager.pumpManager = nil

                // Update UI state
                DispatchQueue.main.async {
                    self.pumpState = nil
                }

                debug(.service, "Pump simulator was reset because simulators are hidden")
            }
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}

extension PumpConfig.StateModel: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        provider.setPumpManager(pumpManager)
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager _: PumpManagerUI) {
        // nothing to do
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
        // TODO:
    }
}
