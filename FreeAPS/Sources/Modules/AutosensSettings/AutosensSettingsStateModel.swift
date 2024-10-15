import Observation
import SwiftUI

extension AutosensSettings {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        @ObservationIgnored @Injected() var storage: FileStorage!

        var units: GlucoseUnits = .mgdL

        var autosensMax: Decimal = 1.2
        var autosensMin: Decimal = 0.7
        var rewindResetsAutosens: Bool = true

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

extension AutosensSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
