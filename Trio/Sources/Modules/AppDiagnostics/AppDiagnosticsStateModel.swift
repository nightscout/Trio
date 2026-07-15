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

        /// Derives the 3-state option from the two underlying flags. Both
        /// streams are enabled by default (`nil` ⇒ on), so an untouched
        /// install surfaces `.full` until the user opts out here.
        func loadDiagnostics() {
            let crashlytics = PropertyPersistentFlags.shared.diagnosticsSharingEnabled ?? true
            let telemetry = PropertyPersistentFlags.shared.telemetryEnabled ?? true
            diagnosticsSharingOption = DiagnosticsSharingOption(
                crashlyticsEnabled: crashlytics,
                telemetryEnabled: telemetry
            )
        }

        /// Persists the current diagnostics sharing option to both underlying flags
        /// and applies it to Crashlytics + the telemetry sender.
        func applyDiagnostics() {
            let wasTelemetryOn = PropertyPersistentFlags.shared.telemetryEnabled != false

            PropertyPersistentFlags.shared.diagnosticsSharingEnabled = diagnosticsSharingOption.crashlyticsEnabled
            PropertyPersistentFlags.shared.telemetryEnabled = diagnosticsSharingOption.telemetryEnabled
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(diagnosticsSharingOption.crashlyticsEnabled)

            // Fire an inaugural send on a fresh re-opt-in so the first data
            // point arrives immediately rather than 24h later.
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

/// Three-state diagnostics-sharing selection.
///
/// Maps to a pair of independent `Bool?` flags in `PropertyPersistentFlags`:
/// `diagnosticsSharingEnabled` (Crashlytics) and `telemetryEnabled` (the
/// anonymous-usage POST). See `TelemetryClient`.
enum DiagnosticsSharingOption: String, Equatable, CaseIterable, Identifiable {
    case full
    case crashOnly
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full:
            return String(localized: "Enable Full Sharing")
        case .crashOnly:
            return String(localized: "Crash Reports Only")
        case .disabled:
            return String(localized: "Disable Sharing")
        }
    }

    var caption: String {
        switch self {
        case .full:
            return String(localized: "Share anonymous crash reports + usage data.")
        case .crashOnly:
            return String(localized: "Share only crash reports — no usage data.")
        case .disabled:
            return String(localized: "Do not share any diagnostic data.")
        }
    }

    var crashlyticsEnabled: Bool {
        switch self {
        case .crashOnly,
             .full: return true
        case .disabled: return false
        }
    }

    var telemetryEnabled: Bool {
        switch self {
        case .full: return true
        case .crashOnly,
             .disabled: return false
        }
    }

    init(crashlyticsEnabled: Bool, telemetryEnabled: Bool) {
        switch (crashlyticsEnabled, telemetryEnabled) {
        case (true, true): self = .full
        case (true, false): self = .crashOnly
        case (false, true): self = .full // unreachable in normal flow
        case (false, false): self = .disabled
        }
    }
}
