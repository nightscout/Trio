import Combine
import SwiftUI

extension GlucoseAlerts {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL
        @Published var glucoseBadge = false

        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.glucoseBadge, on: $glucoseBadge) { glucoseBadge = $0 }
        }
    }
}

extension GlucoseAlerts.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
