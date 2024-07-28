import SwiftUI

extension AutosensSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL

        @Published var autosensMax: Decimal = 1.2
        @Published var autosensMin: Decimal = 0.7
        @Published var rewindResetsAutosens: Bool = true

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units

            autosensMax = settings.preferences.autosensMax
            autosensMin = settings.preferences.autosensMin
            rewindResetsAutosens = settings.preferences.rewindResetsAutosens
        }

        var isSettingUnchanged: Bool {
            preferences.autosensMax == autosensMax &&
                preferences.autosensMin == autosensMin &&
                preferences.rewindResetsAutosens == rewindResetsAutosens
        }

        func saveIfChanged() {
            if !isSettingUnchanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()

                newSettings.autosensMax = autosensMax
                newSettings.autosensMin = autosensMin
                newSettings.rewindResetsAutosens = rewindResetsAutosens

                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
