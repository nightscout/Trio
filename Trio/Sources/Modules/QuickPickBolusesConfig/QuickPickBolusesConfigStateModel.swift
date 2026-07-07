import SwiftUI

extension QuickPickBolusesConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var enableQuickBolus: Bool = false
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() {
            subscribeSetting(\.enableQuickBolus, on: $enableQuickBolus) { enableQuickBolus = $0 }
            units = settingsManager.settings.units
        }
    }
}

extension QuickPickBolusesConfig.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        units = settings.units
    }
}
