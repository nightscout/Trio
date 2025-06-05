import SwiftUI

extension Adjustments.StateModel {
    /// Returns a description of how insulin doses are adjusted based on percentage.
    func percentageDescription(_ percent: Double) -> Text? {
        if percent.isNaN || percent == 100 { return nil }

        var description: String = "Insulin doses will be "

        if percent < 100 {
            description += "decreased by "
        } else {
            description += "increased by "
        }

        let deviationFrom100 = abs(percent - 100)
        description += String(format: "%.0f% %.", deviationFrom100)

        return Text(description)
    }

    /// Checks if the device is using a 24-hour time format.
    func is24HourFormat() -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let dateString = formatter.string(from: Date())

        return !dateString.contains("AM") && !dateString.contains("PM")
    }

    /// Converts a given hour to a 12-hour AM/PM format string.
    func convertTo12HourFormat(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"

        let calendar = Calendar.current
        let components = DateComponents(hour: hour)
        let date = calendar.date(from: components) ?? Date()

        return formatter.string(from: date)
    }

    /// Formats a given 24-hour time number as a two-digit string.
    func format24Hour(_ hour: Int) -> String {
        String(format: "%02d", hour)
    }

    /// Converts a duration in minutes to a formatted string (e.g., "1 h 30 m").
    func formatHoursAndMinutes(_ durationInMinutes: Int) -> String {
        let hours = durationInMinutes / 60
        let minutes = durationInMinutes % 60

        switch (hours, minutes) {
        case let (0, m):
            return "\(m)\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
        case let (h, 0):
            return "\(h)\u{00A0}" + String(localized: "h", comment: "h")
        default:
            return hours.description + "\u{00A0}" + String(localized: "h", comment: "h") + "\u{00A0}" + minutes
                .description + "\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
        }
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
