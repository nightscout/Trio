import SwiftUI

extension TargetBehavoir {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL

        @Published var highTemptargetRaisesSensitivity: Bool = false
        @Published var lowTemptargetLowersSensitivity: Bool = false
        @Published var sensitivityRaisesTarget: Bool = false
        @Published var resistanceLowersTarget: Bool = false
        @Published var halfBasalExerciseTarget: Decimal = 160

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units

            highTemptargetRaisesSensitivity = settings.preferences.highTemptargetRaisesSensitivity
            lowTemptargetLowersSensitivity = settings.preferences.lowTemptargetLowersSensitivity
            sensitivityRaisesTarget = settings.preferences.sensitivityRaisesTarget
            resistanceLowersTarget = settings.preferences.resistanceLowersTarget
            halfBasalExerciseTarget = settings.preferences.halfBasalExerciseTarget

            halfBasalExerciseTarget = settings
                .preferences.halfBasalExerciseTarget
        }

        var isSettingUnchanged: Bool {
            preferences.highTemptargetRaisesSensitivity == highTemptargetRaisesSensitivity &&
                preferences.lowTemptargetLowersSensitivity == lowTemptargetLowersSensitivity &&
                preferences.sensitivityRaisesTarget == sensitivityRaisesTarget &&
                preferences.resistanceLowersTarget == resistanceLowersTarget &&
                preferences.halfBasalExerciseTarget == halfBasalExerciseTarget
        }

        func saveIfChanged() {
            if !isSettingUnchanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()

                newSettings.highTemptargetRaisesSensitivity = highTemptargetRaisesSensitivity
                newSettings.lowTemptargetLowersSensitivity = lowTemptargetLowersSensitivity
                newSettings.sensitivityRaisesTarget = sensitivityRaisesTarget
                newSettings.resistanceLowersTarget = resistanceLowersTarget
                newSettings.halfBasalExerciseTarget = halfBasalExerciseTarget

                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}

extension TargetBehavoir.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
