import Observation
import SwiftUI

extension AutosensSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        var units: GlucoseUnits = .mgdL

        @Published var autosensMax: Decimal = 1.2
        @Published var autosensMin: Decimal = 0.7
        @Published var rewindResetsAutosens: Bool = true

        override func subscribe() {
            units = settingsManager.settings.units

            subscribePreferencesSetting(\.autosensMax, on: $autosensMax) { autosensMax = $0 }
            subscribePreferencesSetting(\.autosensMin, on: $autosensMin) { autosensMin = $0 }
            subscribePreferencesSetting(\.rewindResetsAutosens, on: $rewindResetsAutosens) { rewindResetsAutosens = $0 }
        }
    }
}

extension AutosensSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
