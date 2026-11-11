import SwiftUI

extension Adjustments.StateModel {
    /// Returns a description of how insulin doses are adjusted based on percentage.
    func percentageDescription(_ percent: Double) -> Text? {
        if percent.isNaN || percent == 100 { return nil }

        let change = (abs(percent - 100) / 100).formatted(.wholePercent)
        return percent < 100
            ? Text(
                "Insulin doses will be decreased by \(change).",
                comment: "Adjustment footer; the value is a percentage, e.g. 20%"
            )
            : Text(
                "Insulin doses will be increased by \(change).",
                comment: "Adjustment footer; the value is a percentage, e.g. 20%"
            )
    }

    /// Converts hours and minutes to total minutes as a `Decimal`.
    func convertToMinutes(_ hours: Int, _ minutes: Int) -> Decimal {
        let totalMinutes = (hours * 60) + minutes
        return Decimal(max(0, totalMinutes))
    }
}

extension PickerSettingsProvider {
    /// Generates picker values based on a setting, optionally rounding minimum to the nearest step.
    func generatePickerValues(from setting: PickerSetting, units: GlucoseUnits, roundMinToStep: Bool) -> [Decimal] {
        if !roundMinToStep {
            return generatePickerValues(from: setting, units: units)
        }

        // Adjust min to be divisible by step
        var newSetting = setting
        var min = Double(newSetting.min)
        let step = Double(newSetting.step)
        let remainder = min.truncatingRemainder(dividingBy: step)
        if remainder != 0 {
            // Move min up to the next value divisible by targetStep
            min += (step - remainder)
        }

        newSetting.min = Decimal(min)

        return generatePickerValues(from: newSetting, units: units)
    }
}
