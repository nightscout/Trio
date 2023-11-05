import SwiftUI

extension Dynamic {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var useNewFormula: Bool = false
        @Published var enableDynamicCR: Bool = false
        @Published var sigmoid: Bool = false
        @Published var adjustmentFactor: Decimal = 0.5
        @Published var weightPercentage: Decimal = 0.65
        @Published var tddAdjBasal: Bool = false
        @Published var threshold_setting: Decimal = 65
        @Published var unit: GlucoseUnits = .mmolL

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            unit = settingsManager.settings.units
            useNewFormula = settings.preferences.useNewFormula
            enableDynamicCR = settings.preferences.enableDynamicCR
            sigmoid = settings.preferences.sigmoid
            adjustmentFactor = settings.preferences.adjustmentFactor
            weightPercentage = settings.preferences.weightPercentage
            tddAdjBasal = settings.preferences.tddAdjBasal

            if unit == .mmolL {
                threshold_setting = settings.preferences.threshold_setting.asMmolL
            } else {
                threshold_setting = settings.preferences.threshold_setting
            }
        }

        var unChanged: Bool {
            preferences.enableDynamicCR == enableDynamicCR &&
                preferences.adjustmentFactor == adjustmentFactor &&
                preferences.sigmoid == sigmoid &&
                preferences.tddAdjBasal == tddAdjBasal &&
                preferences.threshold_setting == convertBack(threshold_setting) &&
                preferences.useNewFormula == useNewFormula &&
                preferences.weightPercentage == weightPercentage
        }

        func convertBack(_ glucose: Decimal) -> Decimal {
            if unit == .mmolL {
                return glucose.asMgdL
            }
            return glucose
        }

        func saveIfChanged() {
            if !unChanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
                newSettings.enableDynamicCR = enableDynamicCR
                newSettings.adjustmentFactor = adjustmentFactor
                newSettings.sigmoid = sigmoid
                newSettings.tddAdjBasal = tddAdjBasal
                newSettings.threshold_setting = convertBack(threshold_setting)
                newSettings.useNewFormula = useNewFormula
                newSettings.weightPercentage = weightPercentage
                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
