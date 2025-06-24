import LoopKit
import LoopKitUI
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
