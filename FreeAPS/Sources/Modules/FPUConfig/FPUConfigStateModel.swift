import SwiftUI

extension FPUConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var maxCarbs: Decimal = 250
        @Published var maxFat: Decimal = 250
        @Published var maxProtein: Decimal = 250
        @Published var individualAdjustmentFactor: Decimal = 0
        @Published var timeCap: Decimal = 0
        @Published var minuteInterval: Decimal = 0
        @Published var delay: Decimal = 0

        override func subscribe() {
            subscribeSetting(\.maxCarbs, on: $maxCarbs) { maxCarbs = $0 }
            subscribeSetting(\.maxFat, on: $maxFat) { maxFat = $0 }
            subscribeSetting(\.maxProtein, on: $maxProtein) { maxProtein = $0 }
            subscribeSetting(\.timeCap, on: $timeCap.map(Int.init), initial: {
                let value = max(min($0, 12), 5)
                timeCap = Decimal(value)
            }, map: {
                $0
            })

            subscribeSetting(\.minuteInterval, on: $minuteInterval.map(Int.init), initial: {
                let value = max(min($0, 60), 10)
                minuteInterval = Decimal(value)
            }, map: {
                $0
            })

            subscribeSetting(\.delay, on: $delay.map(Int.init), initial: {
                let value = max(min($0, 120), 60)
                delay = Decimal(value)
            }, map: {
                $0
            })

            subscribeSetting(\.individualAdjustmentFactor, on: $individualAdjustmentFactor, initial: {
                let value = max(min($0, 1.2), 0.1)
                individualAdjustmentFactor = value
            }, map: {
                $0
            })
        }
    }
}
