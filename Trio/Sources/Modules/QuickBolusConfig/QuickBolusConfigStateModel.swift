import SwiftUI

extension QuickBolusConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var enableQuickBolus: Bool = false
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() {
            subscribeSetting(\.enableQuickBolus, on: $enableQuickBolus) { enableQuickBolus = $0 }
            units = settingsManager.settings.units
        }
    }
}

extension QuickBolusConfig.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        units = settings.units
    }
}
