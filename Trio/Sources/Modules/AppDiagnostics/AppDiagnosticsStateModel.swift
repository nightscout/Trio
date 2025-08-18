import FirebaseCrashlytics
import Observation
import SwiftUI

extension AppDiagnostics {
    @Observable final class StateModel: BaseStateModel<Provider> {
        // MARK: - Diagnostics Sharing Option

        var diagnosticsSharingOption: DiagnosticsSharingOption = .enabled

        override func subscribe() {
            loadDiagnostics()
        }

        /// Loads the diagnostics sharing option from UserDefaults as a boolean.
        func loadDiagnostics() {
            if let storedDiagnosticsSharingOption = PropertyPersistentFlags.shared.diagnosticsSharingEnabled {
                diagnosticsSharingOption = storedDiagnosticsSharingOption ? .enabled : .disabled
            } else {
                diagnosticsSharingOption = .enabled
            }
        }

        /// Persists the current diagnostics sharing option to UserDefaults as a boolean.
        func applyDiagnostics() {
            let booleanValue: Bool = diagnosticsSharingOption == .enabled
            PropertyPersistentFlags.shared.diagnosticsSharingEnabled = booleanValue
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(booleanValue)
        }
    }
}

extension AppDiagnostics.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {}
}
