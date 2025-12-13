import Foundation

/// Represents days of the week for therapy profile scheduling.
/// Uses Calendar.Component.weekday values (1 = Sunday, 7 = Saturday)
enum Weekday: Int, CaseIterable, Codable, Comparable, Identifiable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    /// Returns the weekday for today
    static var today: Weekday {
        let weekdayComponent = Calendar.current.component(.weekday, from: Date())
        return Weekday(rawValue: weekdayComponent) ?? .sunday
    }

    /// Returns weekdays (Monday through Friday)
    static var weekdays: Set<Weekday> {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }

    /// Returns weekend days (Saturday and Sunday)
    static var weekend: Set<Weekday> {
        [.saturday, .sunday]
    }

    /// Returns all days as a set
    static var allDays: Set<Weekday> {
        Set(Weekday.allCases)
    }

    /// Localized full name of the day (e.g., "Monday")
    var localizedName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        // weekdaySymbols is 0-indexed (Sunday = 0), rawValue is 1-indexed
        return formatter.weekdaySymbols[rawValue - 1]
    }

    /// Localized short name of the day (e.g., "Mon")
    var shortName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.shortWeekdaySymbols[rawValue - 1]
    }

    /// Very short name (e.g., "M" for Monday)
    var veryShortName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.veryShortWeekdaySymbols[rawValue - 1]
    }

    /// Comparable conformance - allows sorting days in calendar order
    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension Weekday: JSON {}

extension Set where Element == Weekday {
    /// Formats a set of weekdays into a human-readable string
    /// Examples: "Weekdays", "Weekends", "Mon, Wed, Fri", "Every day"
    var formattedString: String {
        if self == Weekday.allDays {
            return NSLocalizedString("Every day", comment: "All days selected")
        }
        if self == Weekday.weekdays {
            return NSLocalizedString("Weekdays", comment: "Monday through Friday")
        }
        if self == Weekday.weekend {
            return NSLocalizedString("Weekends", comment: "Saturday and Sunday")
        }
        if isEmpty {
            return NSLocalizedString("No days", comment: "No days selected")
        }

        let sortedDays = sorted()
        return sortedDays.map(\.shortName).joined(separator: ", ")
    }
}
