import SwiftUI

extension BolusCalculatorConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL
        @Published var overrideFactor: Decimal = 0
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var sweetMeals: Bool = false
        @Published var sweetMealFactor: Decimal = 0
        @Published var displayPresets: Bool = true
        @Published var confirmBolusWhenVeryLowGlucose: Bool = false

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.overrideFactor, on: $overrideFactor) { overrideFactor = $0 }
            subscribeSetting(\.fattyMeals, on: $fattyMeals) { fattyMeals = $0 }
            subscribeSetting(\.displayPresets, on: $displayPresets) { displayPresets = $0 }
            subscribeSetting(\.fattyMealFactor, on: $fattyMealFactor) { fattyMealFactor = $0 }
            subscribeSetting(\.sweetMeals, on: $sweetMeals) { sweetMeals = $0 }
            subscribeSetting(\.sweetMealFactor, on: $sweetMealFactor) { sweetMealFactor = $0 }
            subscribeSetting(\.confirmBolus, on: $confirmBolusWhenVeryLowGlucose) { confirmBolusWhenVeryLowGlucose = $0 }
        }
    }
}

extension BolusCalculatorConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
