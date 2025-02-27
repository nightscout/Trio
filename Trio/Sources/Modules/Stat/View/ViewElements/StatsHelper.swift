import Foundation
import SwiftUI

struct StatsHelper {
    /// Returns the time interval length for the visible domain based on the selected duration.
    /// - Parameter selectedDuration: The selected time interval for statistics.
    /// - Returns: The time interval in seconds.
    static func visibleDomainLength(for selectedDuration: Stat.StateModel.StatsTimeInterval) -> TimeInterval {
        switch selectedDuration {
        case .Day: return 24 * 3600
        case .Week: return 7 * 24 * 3600
        case .Month: return 30 * 24 * 3600
        case .Total: return 90 * 24 * 3600
        }
    }

    /// Computes the visible date range based on the scroll position and selected duration.
    /// - Parameters:
    ///   - scrollPosition: The current scroll position in the chart.
    ///   - selectedDuration: The selected time interval for statistics.
    /// - Returns: A tuple containing the start and end dates of the visible range.
    static func visibleDateRange(
        from scrollPosition: Date,
        for selectedDuration: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let end = scrollPosition.addingTimeInterval(visibleDomainLength(for: selectedDuration))
        return (scrollPosition, end)
    }

    /// Returns the appropriate date format style based on the selected time interval.
    /// - Parameter selectedDuration: The selected time interval for statistics.
    /// - Returns: A Date.FormatStyle configured for the current time interval.
    static func dateFormat(for selectedDuration: Stat.StateModel.StatsTimeInterval) -> Date.FormatStyle {
        switch selectedDuration {
        case .Day: return .dateTime.hour()
        case .Week: return .dateTime.weekday(.abbreviated)
        case .Month: return .dateTime.day()
        case .Total: return .dateTime.month(.abbreviated)
        }
    }

    /// Returns DateComponents for aligning dates based on the selected duration.
    /// - Parameter selectedDuration: The selected time interval for statistics.
    /// - Returns: DateComponents configured for the appropriate alignment.
    static func alignmentComponents(for selectedDuration: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        switch selectedDuration {
        case .Day: return DateComponents(hour: 0)
        case .Week: return DateComponents(weekday: 2)
        case .Month,
             .Total: return DateComponents(day: 1)
        }
    }

    /// Returns the initial scroll position date based on the selected duration.
    /// - Parameter selectedDuration: The selected time interval for statistics.
    /// - Returns: A Date representing the initial scroll position.
    static func getInitialScrollPosition(for selectedDuration: Stat.StateModel.StatsTimeInterval) -> Date {
        let calendar = Calendar.current
        let now = Date()

        switch selectedDuration {
        case .Day: return calendar.date(byAdding: .day, value: -1, to: now)!
        case .Week: return calendar.date(byAdding: .day, value: -7, to: now)!
        case .Month: return calendar.date(byAdding: .month, value: -1, to: now)!
        case .Total: return calendar.date(byAdding: .month, value: -3, to: now)!
        }
    }

    /// Checks if two dates belong to the same time unit based on the selected duration.
    /// - Parameters:
    ///   - date1: The first date.
    ///   - date2: The second date.
    ///   - selectedDuration: The selected time interval for statistics.
    /// - Returns: A Boolean indicating whether the two dates are in the same time unit.
    static func isSameTimeUnit(_ date1: Date, _ date2: Date, for selectedDuration: Stat.StateModel.StatsTimeInterval) -> Bool {
        let calendar = Calendar.current
        switch selectedDuration {
        case .Day:
            return calendar.isDate(date1, equalTo: date2, toGranularity: .hour)
        default:
            return calendar.isDate(date1, inSameDayAs: date2)
        }
    }

    /// Formats the visible date range into a human-readable string.
    /// - Parameters:
    ///   - start: The start date of the range.
    ///   - end: The end date of the range.
    ///   - selectedDuration: The selected time interval for statistics.
    /// - Returns: A formatted string representing the visible date range.
    static func formatVisibleDateRange(from start: Date, to end: Date, for _: Stat.StateModel.StatsTimeInterval) -> String {
        let calendar = Calendar.current
        let today = Date()

        let formatDate: (Date) -> String = { date in
            if calendar.isDate(date, inSameDayAs: today) {
                return "Today"
            } else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
                return "Yesterday"
            } else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!) {
                return "Tomorrow"
            } else {
                return date.formatted(.dateTime.day().month())
            }
        }

        let startText = formatDate(start)
        let endText = formatDate(end)

        return startText == endText ? startText : "\(startText) - \(endText)"
    }
}
