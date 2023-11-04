import SwiftUI

extension BolusCalculatorConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var overrideFactor: Decimal = 0
        @Published var useCalc: Bool = false
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var sweetMeals: Bool = false
        @Published var sweetMealFactor: Decimal = 0
        @Published var insulinReqPercentage: Decimal = 70
        override func subscribe() {
            subscribeSetting(\.overrideFactor, on: $overrideFactor, initial: {
                let value = max(min($0, 1.2), 0.1)
                overrideFactor = value
            }, map: {
                $0
            })
            subscribeSetting(\.useCalc, on: $useCalc) { useCalc = $0 }
            subscribeSetting(\.fattyMeals, on: $fattyMeals) { fattyMeals = $0 }
            subscribeSetting(\.fattyMealFactor, on: $fattyMealFactor, initial: {
                let value = max(min($0, 1.2), 0.1)
                fattyMealFactor = value
            }, map: {
                $0
            })
            subscribeSetting(\.sweetMeals, on: $sweetMeals) { sweetMeals = $0 }
            subscribeSetting(\.sweetMealFactor, on: $sweetMealFactor, initial: {
                let value = max(min($0, 5), 1)
                sweetMealFactor = value
            }, map: {
                $0
            })
            subscribeSetting(\.insulinReqPercentage, on: $insulinReqPercentage) { insulinReqPercentage = $0 }
        }
    }
}
