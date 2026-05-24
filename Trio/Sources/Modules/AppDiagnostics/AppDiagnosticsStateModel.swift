import FirebaseCrashlytics
import Observation
import SwiftUI

extension AppDiagnostics {
    @Observable final class StateModel: BaseStateModel<Provider> {
        // MARK: - Diagnostics Sharing Option

        var diagnosticsSharingOption: DiagnosticsSharingOption = .full

        override func subscribe() {
            loadDiagnostics()
        }

        /// Derives the 3-state option from the two underlying flags. Defaults
        /// to `.full` for fresh installs (opt-out). For pre-telemetry users
        /// who have Crashlytics on but haven't seen the migration sheet, we
        /// surface `.crashOnly` until they pick — never auto-upgrade to
        /// `.full` without an explicit decision.
        func loadDiagnostics() {
            let crashlytics = PropertyPersistentFlags.shared.diagnosticsSharingEnabled ?? true
            let telemetryDecided = PropertyPersistentFlags.shared.telemetryConsentDecisionMade == true
            let telemetry = telemetryDecided
                ? (PropertyPersistentFlags.shared.telemetryEnabled ?? false)
                : false
            diagnosticsSharingOption = DiagnosticsSharingOption(
                crashlyticsEnabled: crashlytics,
                telemetryEnabled: telemetry
            )
        }

        /// Persists the current diagnostics sharing option to both underlying flags
        /// and applies it to Crashlytics + the telemetry sender.
        func applyDiagnostics() {
            let wasTelemetryOn = PropertyPersistentFlags.shared.telemetryEnabled == true

            PropertyPersistentFlags.shared.diagnosticsSharingEnabled = diagnosticsSharingOption.crashlyticsEnabled
            PropertyPersistentFlags.shared.telemetryEnabled = diagnosticsSharingOption.telemetryEnabled
            PropertyPersistentFlags.shared.telemetryConsentDecisionMade = true
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(diagnosticsSharingOption.crashlyticsEnabled)

            // Fire an inaugural send on a fresh opt-in so the first data point
            // arrives at the moment of consent rather than 24h later.
            if diagnosticsSharingOption.telemetryEnabled, !wasTelemetryOn {
                TelemetryClient.shared.scheduleRecurring()
                Task.detached { await TelemetryClient.shared.maybeSend() }
            }
        }
    }
}

extension AppDiagnostics.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {}
}
