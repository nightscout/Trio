import SwiftUI

extension AlgorithmAdvancedSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL

        @Published var maxDailySafetyMultiplier: Decimal = 3
        @Published var currentBasalSafetyMultiplier: Decimal = 4
        @Published var useCustomPeakTime: Bool = false
        @Published var insulinPeakTime: Decimal = 75
        @Published var skipNeutralTemps: Bool = false
        @Published var unsuspendIfNoTemp: Bool = false
        @Published var suspendZerosIOB: Bool = false
        @Published var min5mCarbimpact: Decimal = 8
        @Published var autotuneISFAdjustmentFraction: Decimal = 1.0
        @Published var remainingCarbsFraction: Decimal = 1.0
        @Published var remainingCarbsCap: Decimal = 90
        @Published var noisyCGMTargetMultiplier: Decimal = 1.3

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units

            maxDailySafetyMultiplier = settings.preferences.maxDailySafetyMultiplier
            currentBasalSafetyMultiplier = settings.preferences.currentBasalSafetyMultiplier
            useCustomPeakTime = settings.preferences.useCustomPeakTime
            insulinPeakTime = settings.preferences.insulinPeakTime
            skipNeutralTemps = settings.preferences.skipNeutralTemps
            unsuspendIfNoTemp = settings.preferences.unsuspendIfNoTemp
            suspendZerosIOB = settings.preferences.suspendZerosIOB
            min5mCarbimpact = settings.preferences.min5mCarbimpact
            autotuneISFAdjustmentFraction = settings.preferences.autotuneISFAdjustmentFraction
            remainingCarbsFraction = settings.preferences.remainingCarbsFraction
            remainingCarbsCap = settings.preferences.remainingCarbsCap
            noisyCGMTargetMultiplier = settings.preferences.noisyCGMTargetMultiplier
        }

        var isSettingUnchanged: Bool {
            preferences.maxDailySafetyMultiplier == maxDailySafetyMultiplier &&
                preferences.currentBasalSafetyMultiplier == currentBasalSafetyMultiplier &&
                preferences.useCustomPeakTime == useCustomPeakTime &&
                preferences.insulinPeakTime == insulinPeakTime &&
                preferences.skipNeutralTemps == skipNeutralTemps &&
                preferences.unsuspendIfNoTemp == unsuspendIfNoTemp &&
                preferences.suspendZerosIOB == suspendZerosIOB &&
                preferences.min5mCarbimpact == min5mCarbimpact &&
                preferences.autotuneISFAdjustmentFraction == autotuneISFAdjustmentFraction &&
                preferences.remainingCarbsFraction == remainingCarbsFraction &&
                preferences.remainingCarbsCap == remainingCarbsCap &&
                preferences.noisyCGMTargetMultiplier == noisyCGMTargetMultiplier
        }

        func saveIfChanged() {
            if !isSettingUnchanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()

                newSettings.maxDailySafetyMultiplier = maxDailySafetyMultiplier
                newSettings.currentBasalSafetyMultiplier = currentBasalSafetyMultiplier
                newSettings.useCustomPeakTime = useCustomPeakTime
                newSettings.insulinPeakTime = insulinPeakTime
                newSettings.skipNeutralTemps = skipNeutralTemps
                newSettings.unsuspendIfNoTemp = unsuspendIfNoTemp
                newSettings.suspendZerosIOB = suspendZerosIOB
                newSettings.min5mCarbimpact = min5mCarbimpact
                newSettings.autotuneISFAdjustmentFraction = autotuneISFAdjustmentFraction
                newSettings.remainingCarbsFraction = remainingCarbsFraction
                newSettings.remainingCarbsCap = remainingCarbsCap
                newSettings.noisyCGMTargetMultiplier = noisyCGMTargetMultiplier

                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
