import Foundation

enum MinutesFromMidnightError: LocalizedError, Equatable {
    case invalidCalendar

    var errorDescription: String? {
        switch self {
        case .invalidCalendar:
            return "Unable to extract hours and minutes from the current calendar"
        }
    }
}

extension Date {
    /// Returns the total minutes elapsed since midnight for the current date
    var minutesSinceMidnight: Int? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: self)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return hour * 60 + minute
    }

    var minutesSinceMidnightWithPrecision: Decimal? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: self)

        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second,
              let nanosecond = components.nanosecond
        else {
            return nil
        }

        // Convert nanoseconds to milliseconds and round
        let milliseconds = (Decimal(nanosecond) / 1_000_000).rounded()

        let baseMinutes = Decimal(hour * 60 + minute)
        let secondsAsMinutes = Decimal(second) / Decimal(60)
        let millisecondsAsMinutes = milliseconds / Decimal(60000)

        return baseMinutes + secondsAsMinutes + millisecondsAsMinutes
    }

    /// Checks if the current time falls within the specified range of minutes
    /// - Parameters:
    ///   - lowerBound: The lower bound in minutes since midnight (inclusive)
    ///   - upperBound: The upper bound in minutes since midnight (exclusive)
    /// - Returns: Boolean indicating if the current time is within the specified range
    func isMinutesFromMidnightWithinRange(lowerBound: Int, upperBound: Int) throws -> Bool {
        guard let currentMinutes = minutesSinceMidnight else {
            throw MinutesFromMidnightError.invalidCalendar
        }
        return currentMinutes >= lowerBound && currentMinutes < upperBound
    }
}
