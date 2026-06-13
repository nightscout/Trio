import Foundation
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
        @Published var hasUnacknowledgedAlert: Bool = false
        @Injected() var bluetoothManager: BluetoothStateManager!
        @Injected() var trioAlertManager: TrioAlertManager!

        override func subscribe() {
            provider.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpState, on: self)
                .store(in: &lifetime)

            hasUnacknowledgedAlert = provider.hasInitialUnacknowledgedAlerts()
            provider.unacknowledgedAlertsPublisher
                .receive(on: DispatchQueue.main)
                .assign(to: \.hasUnacknowledgedAlert, on: self)
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
            trioAlertManager.acknowledgeAllOutstanding()
        }

        // FIXME: Remove before merge. Dev-only buttons for exercising the
    // foreground modal scheduler + background UN delivery paths. The body
    // text is intentionally technobabble — it's for developers verifying
    // pipeline wiring, not end users.
    func fireTestAlert(critical: Bool) {
            let identifier = Alert.Identifier(
                managerIdentifier: "Trio.test",
                alertIdentifier: "test-\(UUID().uuidString.prefix(8))"
            )
            let content = Alert.Content(
                title: critical ? "Critical test alert" : "Test alert",
                body: "If you see this banner in-app, the foreground modal scheduler is wired. Background it before tapping to test the UN push path.",
                acknowledgeActionButtonLabel: "OK"
            )
            let alert = Alert(
                identifier: identifier,
                foregroundContent: content,
                backgroundContent: content,
                trigger: .immediate,
                interruptionLevel: critical ? .critical : .timeSensitive
            )
            trioAlertManager.issueAlert(alert)
        }

        func retractTestAlerts() {
            let identifier = Alert.Identifier(managerIdentifier: "Trio.test", alertIdentifier: "test")
            trioAlertManager.retractAlert(identifier: identifier)
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
