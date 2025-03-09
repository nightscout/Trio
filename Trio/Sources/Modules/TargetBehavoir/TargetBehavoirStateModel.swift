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
        @Published var autosensMax: Decimal = 1

        override func subscribe() {
            units = settingsManager.settings.units
            autosensMax = settingsManager.preferences.autosensMax
            subscribePreferencesSetting(\.highTemptargetRaisesSensitivity, on: $highTemptargetRaisesSensitivity) {
                highTemptargetRaisesSensitivity = $0 }
            subscribePreferencesSetting(\.lowTemptargetLowersSensitivity, on: $lowTemptargetLowersSensitivity) {
                lowTemptargetLowersSensitivity = $0 }
            subscribePreferencesSetting(\.sensitivityRaisesTarget, on: $sensitivityRaisesTarget) { sensitivityRaisesTarget = $0 }
            subscribePreferencesSetting(\.resistanceLowersTarget, on: $resistanceLowersTarget) { resistanceLowersTarget = $0 }
            subscribePreferencesSetting(\.halfBasalExerciseTarget, on: $halfBasalExerciseTarget) { halfBasalExerciseTarget = $0 }
        }
    }
}

extension TargetBehavoir.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
