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

    static func visibleDomainLength(
        for selectedInterval: Stat.StateModel.StatsTimeInterval,
        at date: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: dayCount(for: selectedInterval), to: start)!
        return end.timeIntervalSince(start)
    }

    static func visibleDateRange(
        from scrollPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current

        let start = calendar.startOfDay(for: scrollPosition)
        let end = calendar.date(byAdding: .day, value: dayCount(for: selectedInterval), to: start)!

        return (start, end)
    }

    // The end of the range is exclusive, so a midnight bucket belongs to the next day.
    static func isStatInRange(_ date: Date, in range: (start: Date, end: Date)) -> Bool {
        date >= range.start && date < range.end
    }

    private static func dateFormat(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date.FormatStyle {
        switch selectedInterval {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .total: return .dateTime.month(.abbreviated)
        }
    }

    static func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
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

    @AxisContentBuilder static func timeOfDayAxisMarks() -> some AxisContent {
        AxisMarks(preset: .aligned, values: .stride(by: .hour, count: 3)) { value in
            if let date = value.as(Date.self) {
                let hour = Calendar.current.component(.hour, from: date)
                switch hour {
                case 0,
                     12:
                    AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                default:
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)), anchor: .top)
                }

                AxisGridLine()
            }
        }
    }

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

    static func getInitialScrollPosition(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let daysBack = dayCount(for: selectedInterval) - 1
        let today = Calendar.current.startOfDay(for: Date())

        return Calendar.current.date(byAdding: .day, value: -daysBack, to: today)!
    }

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

    static func format(_ value: Double, fractionLength: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(fractionLength)))
    }

    static func formatPercentage(_ value: Decimal, fractionLength: Int = 1) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(fractionLength)))
    }

    static func formatPercentage(_ value: Double, fractionLength: Int = 1) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(fractionLength)))
    }

    static func hourRangeText(for date: Date, calendar: Calendar = .current) -> String {
        let hourRange = calendar.date(byAdding: .hour, value: 1, to: date) ?? date

        return date.formatted(.dateTime.hour()) + "-" + hourRange.formatted(.dateTime.hour())
    }

    static func selectionTitle(for date: Date, showHourRange: Bool) -> String {
        let day = date.formatted(.dateTime.month().day().weekday())
        guard showHourRange else { return day }
        return day + "\n" + hourRangeText(for: date)
    }

    static func glucoseThresholds(
        timeInRangeType: TimeInRangeType,
        highLimit: Decimal,
        units: GlucoseUnits
    ) -> [(label: String, color: Color, value: Double)] {
        [
            (
                timeInRangeType.bottomThreshold.formatted(withUnits: units),
                .staticLow,
                Double(timeInRangeType.bottomThreshold).asUnit(units)
            ),
            (
                timeInRangeType.topThreshold.formatted(withUnits: units),
                .staticInRange,
                Double(timeInRangeType.topThreshold).asUnit(units)
            ),
            (
                highLimit.formatted(withUnits: units),
                .staticHigh,
                Double(highLimit.asUnit(units))
            )
        ]
    }

    static func glucoseBandDisplayInfo(
        for band: GlucoseBand,
        units: GlucoseUnits,
        timeInRangeType: TimeInRangeType,
        highLimit: Decimal
    ) -> (label: String, color: Color) {
        switch band {
        case .veryLow: ("<\(Decimal(54).formatted(for: units))", .dynamicRed)
        case .low: (
                "\(Decimal(54).formatted(for: units))-\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units))",
                .dynamicOrange
            )
        case .tight: (
                "\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units))-\(Decimal(timeInRangeType.topThreshold).formatted(for: units))",
                .dynamicGreen
            )
        case .upperMid: (
                "\(Decimal(timeInRangeType.topThreshold).formatted(for: units))-\(highLimit.formatted(for: units))",
                .dynamicTeal
            )
        case .high: ("\(highLimit.formatted(for: units))-\(Decimal(250).formatted(for: units))", .dynamicBlue)
        case .veryHigh: (">\(Decimal(250).formatted(for: units))", .dynamicPurple)
        }
    }

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

    // Invisible point at next midnight so single-day charts span 00:00–23:59.
    static func fullDayDomainAnchor() -> some ChartContent {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight)!

        return PointMark(
            x: .value("Time", nextMidnight),
            y: .value("Dummy", 0)
        )
        .opacity(0)
    }

    static func popoverRow(
        label: LocalizedStringKey,
        formattedValue: String,
        unit: LocalizedStringKey? = nil
    ) -> some View {
        GridRow {
            Text(label)
            Group {
                let value = Text(verbatim: formattedValue).bold()
                if let unit {
                    value + Text(verbatim: "\u{00A0}") + Text(unit).foregroundStyle(.secondary)
                } else {
                    value
                }
            }
            .gridColumnAlignment(.trailing)
            .monospacedDigit()
        }
    }

    static func statRow(
        label: LocalizedStringKey,
        value: Double,
        unit: LocalizedStringKey? = nil,
        showAverageSymbol: Bool,
        fractionLength: Int = 1
    ) -> some View {
        GridRow {
            if showAverageSymbol { Text(verbatim: "ø") + Text(verbatim: "\u{00A0}") + Text(label) } else { Text(label) }

            let formattedValue = Text(verbatim: format(value, fractionLength: fractionLength))
            if let unit { formattedValue + Text(verbatim: "\u{00A0}") + Text(unit) } else { formattedValue }
        }
    }

    static func statView(title: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }

    static func summaryStats(for values: [Int]) -> (average: Double, median: Double, standardDeviation: Double) {
        guard !values.isEmpty else { return (0, 0, 0) }

        let total = values.reduce(0, +)
        let average = Double(total) / Double(values.count)
        let median = percentile(0.5, of: values.map(Double.init).sorted())

        let sumOfSquaredDifferences = values.reduce(0.0) { $0 + pow(Double($1) - average, 2) }
        let standardDeviation = sqrt(sumOfSquaredDifferences / max(Double(values.count - 1), 1))

        return (average, median, standardDeviation)
    }

    static func percentile(_ p: Double, of sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 0 }

        let position = Double(sortedValues.count - 1) * p
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sortedValues[lower] }

        let weight = position - Double(lower)
        return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight
    }
}
