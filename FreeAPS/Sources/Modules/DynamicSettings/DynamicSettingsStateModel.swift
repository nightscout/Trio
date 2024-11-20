import Observation
import SwiftUI

extension DynamicSettings {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        @ObservationIgnored @Injected() var storage: FileStorage!

        var useNewFormula: Bool = false
        var enableDynamicCR: Bool = false
        var sigmoid: Bool = false
        var adjustmentFactor: Decimal = 0.8
        var adjustmentFactorSigmoid: Decimal = 0.5
        var weightPercentage: Decimal = 0.35
        var tddAdjBasal: Bool = false
        var threshold_setting: Decimal = 60
        var units: GlucoseUnits = .mgdL

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units
            useNewFormula = settings.preferences.useNewFormula
            enableDynamicCR = settings.preferences.enableDynamicCR
            sigmoid = settings.preferences.sigmoid
            adjustmentFactor = settings.preferences.adjustmentFactor
            adjustmentFactorSigmoid = settings.preferences.adjustmentFactorSigmoid
            weightPercentage = settings.preferences.weightPercentage
            tddAdjBasal = settings.preferences.tddAdjBasal
            threshold_setting = settings.preferences.threshold_setting
        }

        var unChanged: Bool {
            preferences.enableDynamicCR == enableDynamicCR &&
                preferences.adjustmentFactor == adjustmentFactor &&
                preferences.sigmoid == sigmoid &&
                preferences.adjustmentFactorSigmoid == adjustmentFactorSigmoid &&
                preferences.tddAdjBasal == tddAdjBasal &&
                preferences.threshold_setting == threshold_setting &&
                preferences.useNewFormula == useNewFormula &&
                preferences.weightPercentage == weightPercentage
        }

        func saveIfChanged() {
            if !unChanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
                newSettings.enableDynamicCR = enableDynamicCR
                newSettings.adjustmentFactor = adjustmentFactor
                newSettings.sigmoid = sigmoid
                newSettings.adjustmentFactorSigmoid = adjustmentFactorSigmoid
                newSettings.tddAdjBasal = tddAdjBasal
                newSettings.threshold_setting = threshold_setting
                newSettings.useNewFormula = useNewFormula
                newSettings.weightPercentage = weightPercentage
                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}

extension DynamicSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
