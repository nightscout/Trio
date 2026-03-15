import SwiftUI

extension UserInterfaceSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Published var low: Decimal = 70
        @Published var high: Decimal = 180
        @Published var xGridLines = false
        @Published var yGridLines: Bool = false
        @Published var rulerMarks: Bool = true
        @Published var forecastDisplayType: ForecastDisplayType = .cone
        @Published var showCarbsRequiredBadge: Bool = true
        @Published var carbsRequiredThreshold: Decimal = 0
        @Published var glucoseColorScheme: GlucoseColorScheme = .staticColor
        @Published var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
        @Published var timeInRangeType: TimeInRangeType = .timeInTightRange

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.xGridLines, on: $xGridLines) { xGridLines = $0 }
            subscribeSetting(\.yGridLines, on: $yGridLines) { yGridLines = $0 }
            subscribeSetting(\.rulerMarks, on: $rulerMarks) { rulerMarks = $0 }

            subscribeSetting(\.forecastDisplayType, on: $forecastDisplayType) { forecastDisplayType = $0 }

            subscribeSetting(\.low, on: $low) { low = $0 }

            subscribeSetting(\.high, on: $high) { high = $0 }

            subscribeSetting(\.showCarbsRequiredBadge, on: $showCarbsRequiredBadge) { showCarbsRequiredBadge = $0 }

            subscribeSetting(
                \.carbsRequiredThreshold,
                on: $carbsRequiredThreshold
            ) { carbsRequiredThreshold = $0 }

            subscribeSetting(\.glucoseColorScheme, on: $glucoseColorScheme) { glucoseColorScheme = $0 }

            subscribeSetting(\.eA1cDisplayUnit, on: $eA1cDisplayUnit) { eA1cDisplayUnit = $0 }

            subscribeSetting(\.timeInRangeType, on: $timeInRangeType) { timeInRangeType = $0 }
        }
    }
}

extension UserInterfaceSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
