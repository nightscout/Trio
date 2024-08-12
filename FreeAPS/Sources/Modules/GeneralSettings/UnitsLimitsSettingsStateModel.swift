import SwiftUI

extension UnitsLimitsSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var unitsIndex = 0 // 0 = mg/dl

        @Published var maxIOB: Decimal = 0
        @Published var maxCOB: Decimal = 120

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.units, on: $unitsIndex.map { $0 == 0 ? GlucoseUnits.mgdL : .mmolL }) {
                unitsIndex = $0 == .mgdL ? 0 : 1
            }

            maxIOB = settings.preferences.maxIOB
            maxCOB = settings.preferences.maxCOB
        }

        var isSettingUnchanged: Bool {
            preferences.maxIOB == maxIOB &&
                preferences.maxCOB == maxCOB
        }

        func saveIfChanged() {
            if !isSettingUnchanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()

                newSettings.maxIOB = maxIOB
                newSettings.maxCOB = maxCOB

                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}

extension UnitsLimitsSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
