import Charts
import Foundation
import SwiftUI

struct StatChartUtils {
    static let hourlyWindowDays = 20

    static func dayCount(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Int {
        switch selectedInterval {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .total: return 90
        }
    }

    /// Returns the time interval length for the visible domain based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: The time interval in seconds.
    static func visibleDomainLength(
        for selectedInterval: Stat.StateModel.StatsTimeInterval,
        at date: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: dayCount(for: selectedInterval), to: start)!
        return end.timeIntervalSince(start)
    }

    /// Computes the visible date range based on the scroll position and selected duration.
    /// - Parameters:
    ///   - scrollPosition: The current scroll position in the chart.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A tuple containing the start and end dates of the visible range.
    static func visibleDateRange(
        from scrollPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current

        let start = calendar.startOfDay(for: scrollPosition)
        let end = calendar.date(byAdding: .day, value: dayCount(for: selectedInterval), to: start)!

        return (start, end)
    }

    static func isStatInRange(_ date: Date, in range: (start: Date, end: Date)) -> Bool {
        date >= range.start && date < range.end
    }

    /// Returns the appropriate date format style based on the selected time interval.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: A Date.FormatStyle configured for the current time interval.
    private static func dateFormat(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date.FormatStyle {
        switch selectedInterval {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .total: return .dateTime.month(.abbreviated)
        }
    }

    static func popoverAlignment(
        for selected: Date,
        scrollPosition: Date,
        in interval: Stat.StateModel.StatsTimeInterval
    ) -> Alignment {
        let length = visibleDomainLength(for: interval, at: scrollPosition)
        let pos = selected.timeIntervalSince(scrollPosition) / length

        if pos < 0.25 { return .leading }
        else if pos > 0.75 { return .trailing }

        return .center
    }

    /// Returns the x-axis marks shared by the scrollable, date-based stat charts.
    ///
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: The configured `AxisMarks` for the chart's x-axis.
    @AxisContentBuilder static func dateAxisMarks(
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> some AxisContent {
        let calendar = Calendar.current
        let domainEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!

        AxisMarks(preset: .aligned, values: .stride(by: selectedInterval == .day ? .hour : .day)) { value in
            if let date = value.as(Date.self) {
                let showsLabel = date < domainEnd && {
                    switch selectedInterval {
                    case .day:
                        return calendar.component(.hour, from: date) % 6 == 0
                    case .week:
                        return true
                    case .month:
                        return calendar.component(.weekday, from: date) == calendar.firstWeekday
                    case .total:
                        return calendar.component(.day, from: date) == 1
                    }
                }()

                AxisValueLabel(centered: true) {
                    if showsLabel {
                        Text(date, format: dateFormat(for: selectedInterval)).font(.footnote)
                    }
                }
                if showsLabel {
                    AxisGridLine()
                }
            }
        }
    }

    /// Returns DateComponents for aligning dates based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: DateComponents configured for the appropriate alignment.
    static func alignmentComponents(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        switch selectedInterval {
        case .day: return DateComponents(hour: 0)
        case .week:
            let calendar = Calendar.current
            return DateComponents(weekday: calendar.firstWeekday)
        case .month,
             .total: return DateComponents(day: 1)
        }
    }

    /// Returns the initial scroll position date based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: A Date representing the initial scroll position.
    static func getInitialScrollPosition(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let daysBack = dayCount(for: selectedInterval) - 1
        let today = Calendar.current.startOfDay(for: Date())

        return Calendar.current.date(byAdding: .day, value: -daysBack, to: today)!
    }

    /// Checks if two dates belong to the same time unit based on the selected duration.
    /// - Parameters:
    ///   - date1: The first date.
    ///   - date2: The second date.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A Boolean indicating whether the two dates are in the same time unit.
    static func isSameTimeUnit(
        _ date1: Date,
        _ date2: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Bool {
        let calendar = Calendar.current
        switch selectedInterval {
        case .day:
            return calendar.isDate(date1, equalTo: date2, toGranularity: .hour)
        default:
            return calendar.isDate(date1, inSameDayAs: date2)
        }
    }

    /// Formats the visible date range into a human-readable string.
    /// - Parameters:
    ///   - start: The start date of the range.
    ///   - end: The end date of the range.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A formatted string representing the visible date range.
    static func formatVisibleDateRange(
        from start: Date,
        to end: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> String {
        let calendar = Calendar.current

        let startDay = calendar.startOfDay(for: start)

        if selectedInterval == .day {
            return startDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }

        let formatDate: (Date) -> String = { date in
            date.formatted(.dateTime.day().month())
        }
        let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: end))!

        return "\(formatDate(startDay)) - \(formatDate(inclusiveEnd))"
    }

    static func fullDayDomainAnchor() -> some ChartContent {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight)!

        return PointMark(
            x: .value("Time", nextMidnight),
            y: .value("Dummy", 0)
        )
        .opacity(0) // ensures dummy ChartContent is hidden
    }

    static func popoverRow(label: LocalizedStringKey, value: Double, unit: LocalizedStringKey) -> some View {
        GridRow {
            Text(label)
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .gridColumnAlignment(.trailing).bold()
            Text(unit).foregroundStyle(Color.secondary)
        }
    }

    static func statRow(
        label: LocalizedStringKey,
        value: Double,
        unit: LocalizedStringKey,
        showAverageSymbol: Bool
    ) -> some View {
        GridRow {
            if showAverageSymbol {
                Text("ø") + Text("\u{00A0}") + Text(label)
            } else {
                Text(label)
            }
            Text(value.formatted(.number.precision(.fractionLength(1))))
                + Text("\u{00A0}") + Text(unit)
        }
    }

    /// A helper function to create a `VStack` for each statistic.
    ///
    /// - Parameters:
    ///   - title: The title of the statistic.
    ///   - value: The formatted value to display.
    /// - Returns: A `VStack` with the title and value.
    static func statView(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }

    /// Computes the median value of an array of integers.
    ///
    /// - Parameter array: An array of integers.
    /// - Returns: The median value as a `Double`. Returns `0` if the array is empty.
    static func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    /// Computes the median value of an array of doubles.
    ///
    /// - Parameter array: An array of `Double` values.
    /// - Returns: The median value. Returns `0` if the array is empty.
    static func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    /// Creates a legend item view for use in a chart legend.
    ///
    /// - Parameters:
    ///   - label: The text label for the legend item.
    ///   - color: The color associated with the legend item.
    /// - Returns: A SwiftUI view displaying a colored symbol and a label.
    @ViewBuilder static func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill").foregroundStyle(color)
                .accessibilityHidden(true)
            Text(label).foregroundStyle(Color.secondary)
        }.font(.caption)
    }
}
