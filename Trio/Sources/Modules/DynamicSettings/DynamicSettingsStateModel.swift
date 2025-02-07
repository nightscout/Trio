import Observation
import SwiftUI

extension DynamicSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var useNewFormula: Bool = false
        @Published var enableDynamicCR: Bool = false
        @Published var sigmoid: Bool = false
        @Published var adjustmentFactor: Decimal = 0.8
        @Published var adjustmentFactorSigmoid: Decimal = 0.5
        @Published var weightPercentage: Decimal = 0.65
        @Published var tddAdjBasal: Bool = false
        @Published var threshold_setting: Decimal = 60

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units

            subscribePreferencesSetting(\.useNewFormula, on: $useNewFormula) { useNewFormula = $0 }
            subscribePreferencesSetting(\.enableDynamicCR, on: $enableDynamicCR) { enableDynamicCR = $0 }
            subscribePreferencesSetting(\.sigmoid, on: $sigmoid) { sigmoid = $0 }
            subscribePreferencesSetting(\.adjustmentFactor, on: $adjustmentFactor) { adjustmentFactor = $0 }
            subscribePreferencesSetting(\.adjustmentFactorSigmoid, on: $adjustmentFactorSigmoid) { adjustmentFactorSigmoid = $0 }
            subscribePreferencesSetting(\.weightPercentage, on: $weightPercentage) { weightPercentage = $0 }
            subscribePreferencesSetting(\.tddAdjBasal, on: $tddAdjBasal) { tddAdjBasal = $0 }
            subscribePreferencesSetting(\.threshold_setting, on: $threshold_setting) { threshold_setting = $0 }
        }
    }
}

extension DynamicSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
