import Combine
import SwiftUI

extension GlucoseAlerts {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var fetchGlucoseManager: FetchGlucoseManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var glucoseBadge = false
        @Published var cgmAppInfo: CGMManagerAlertOwnership.OwningApp?

        var cgmProvidesOwnAlerts: Bool { cgmAppInfo != nil }

        override func subscribe() {
            units = settingsManager.settings.units
            refreshCGMOwnership()
            subscribeSetting(\.glucoseBadge, on: $glucoseBadge) { glucoseBadge = $0 }
        }

        /// Re-read whether the active CGM owns its own glucose alerts. The
        /// active manager can change while the user is in CGM settings, so
        /// the alarms view calls this on appear.
        func refreshCGMOwnership() {
            cgmAppInfo = CGMManagerAlertOwnership.owningApp(
                manager: fetchGlucoseManager?.cgmManager,
                sourceType: fetchGlucoseManager?.cgmGlucoseSourceType ?? .none
            )
        }
    }
}

extension GlucoseAlerts.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
