import Foundation

enum CalendarError: LocalizedError, Equatable {
    case invalidCalendar
    case invalidCalendarHourOnly

    var errorDescription: String? {
        switch self {
        case .invalidCalendar:
            return "Unable to extract hours and minutes from the current calendar"
        case .invalidCalendarHourOnly:
            return "Unable to extract hours from the current calendar"
        }
    }
}

/// Calendar-free local time; UTC offset cached between DST transitions.
/// Deliberate exception: the algorithm is meant to stay stateless — this offset cache is the one piece of state we allow.
enum WallClock {
    private struct Interval {
        let start: TimeInterval
        let end: TimeInterval
        let offsetSeconds: Int
        let timeZoneIdentifier: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Interval?

    /// Seconds into the local day (wall clock), in [0, 86400).
    static func secondsIntoDay(of date: Date) -> Double {
        let t = date.timeIntervalSince1970
        let local = t + Double(offsetSeconds(at: date))
        var seconds = local.truncatingRemainder(dividingBy: 86400)
        if seconds < 0 { seconds += 86400 }
        return seconds
    }

    static func offsetSeconds(at date: Date) -> Int {
        let timeZone = TimeZone.current
        let t = date.timeIntervalSince1970

        lock.lock()
        defer { lock.unlock() }
        if let cached,
           cached.timeZoneIdentifier == timeZone.identifier,
           t >= cached.start, t < cached.end
        {
            return cached.offsetSeconds
        }

        let offset = timeZone.secondsFromGMT(for: date)
        let end = timeZone.nextDaylightSavingTimeTransition(after: date)?
            .timeIntervalSince1970 ?? .greatestFiniteMagnitude

        // find the transition preceding `date`
        var start = -TimeInterval.greatestFiniteMagnitude
        var probe = date.addingTimeInterval(-366 * 86400)
        for _ in 0 ..< 16 {
            guard let transition = timeZone.nextDaylightSavingTimeTransition(after: probe),
                  transition.timeIntervalSince1970 <= t
            else { break }
            start = transition.timeIntervalSince1970
            probe = transition
        }

        cached = Interval(start: start, end: end, offsetSeconds: offset, timeZoneIdentifier: timeZone.identifier)
        return offset
    }
}

extension Date {
    /// Returns the hour component for the date using the current timezone
    var hourInLocalTime: Int? {
        Int(WallClock.secondsIntoDay(of: self) / 3600)
    }

    /// Returns the total minutes elapsed since midnight for the current date
    var minutesSinceMidnight: Int? {
        Int(WallClock.secondsIntoDay(of: self) / 60)
    }

    var minutesSinceMidnightWithPrecision: Decimal? {
        let secondsIntoDay = WallClock.secondsIntoDay(of: self)
        let wholeSeconds = Int(secondsIntoDay)
        let nanosecond = Int(((secondsIntoDay - Double(wholeSeconds)) * 1_000_000_000).rounded())

        // Convert nanoseconds to milliseconds and round
        let milliseconds = (Decimal(nanosecond) / 1_000_000).rounded()

        let baseMinutes = Decimal(wholeSeconds / 60)
        let secondsAsMinutes = Decimal(wholeSeconds % 60) / Decimal(60)
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
            throw CalendarError.invalidCalendar
        }
        return currentMinutes >= lowerBound && currentMinutes < upperBound
    }
}

extension Date {
    /// Rounds the date to the nearest minute boundary by rounding the Unix timestamp
    /// - Returns: A new Date with seconds rounded to the nearest minute
    func roundedToNearestMinute() -> Date {
        let timestampInMinutes = timeIntervalSince1970.secondsToMinutes
        let timestampRounded = timestampInMinutes.rounded()
        return Date(timeIntervalSince1970: timestampRounded.minutesToSeconds)
    }
}
