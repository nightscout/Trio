import SwiftUI

extension QuickPickTreatmentsConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var enableQuickPickTreatments: Bool = false
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() {
            subscribeSetting(\.enableQuickPickTreatments, on: $enableQuickPickTreatments) { enableQuickPickTreatments = $0 }
            units = settingsManager.settings.units
        }
    }
}

extension QuickPickTreatmentsConfig.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        units = settings.units
    }
}
