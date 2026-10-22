import Charts
import SwiftUI

enum GlucosePercentileType: String, CaseIterable, Identifiable {
    case minimum = "Min"
    case percentile10 = "10th"
    case percentile25 = "25th"
    case median = "Median"
    case percentile75 = "75th"
    case percentile90 = "90th"
    case maximum = "Max"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .minimum: "Min"
        case .percentile10: "10%"
        case .percentile25: "25%"
        case .median: "Median"
        case .percentile75: "75%"
        case .percentile90: "90%"
        case .maximum: "Max"
        }
    }

    func getValue(from stats: GlucoseDailyPercentileStats) -> Double {
        switch self {
        case .minimum: return stats.minimum
        case .percentile10: return stats.percentile10
        case .percentile25: return stats.percentile25
        case .median: return stats.median
        case .percentile75: return stats.percentile75
        case .percentile90: return stats.percentile90
        case .maximum: return stats.maximum
        }
    }
}

struct GlucoseDailyPercentileChart: View {
    let units: GlucoseUnits
    let timeInRangeType: TimeInRangeType
    let selectedInterval: Stat.StateModel.StatsTimeInterval

    let dailyStats: [GlucoseDailyPercentileStats]
    let readingsByDay: [Date: [GlucoseReading]]

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    @State private var selectedPercentile: GlucosePercentileType?

    private var selectedDayStart: Date? {
        selectedDate.map { Calendar.current.startOfDay(for: $0) }
    }

    private var visibleDailyStats: [GlucoseDailyPercentileStats] {
        dailyStats.filter { stat in
            StatChartUtils.isStatInRange(stat.date, in: visibleDateRange)
        }
    }

    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    private var selectedDateStats: GlucoseDailyPercentileStats? {
        selectedDayStart.flatMap { start in
            dailyStats.first { $0.date == start }
        }
    }

    // Pool raw readings; averaging daily percentiles would weight sparse days equally.
    private func aggregatedVisibleStats(for range: (start: Date, end: Date)) -> GlucoseDailyPercentileStats? {
        let readings = readingsByDay
            .filter { StatChartUtils.isStatInRange($0.key, in: range) }
            .flatMap(\.value)
        guard !readings.isEmpty else { return nil }

        return Stat.StateModel.dailyPercentileStats(date: range.start, readings: readings)
    }

    private var detailViewData: (data: GlucoseDailyPercentileStats, dateText: String)? {
        if let start = selectedDayStart {
            let data = selectedDateStats ?? GlucoseDailyPercentileStats(date: start)
            return (data, StatChartUtils.formatDate(start))
        }
        let range = visibleDateRange
        if let aggregatedData = aggregatedVisibleStats(for: range) {
            return (aggregatedData, StatChartUtils.formatVisibleDateRange(
                from: range.start,
                to: range.end,
                for: selectedInterval
            ))
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(units.rawValue)
                .foregroundStyle(.secondary)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .trailing)

            boxplotChart
                .frame(height: 300)

            if let viewData = detailViewData {
                GlucoseDailyPercentileDetailView(
                    dayData: viewData.data,
                    units: units,
                    dateRangeText: viewData.dateText,
                    selectedPercentile: $selectedPercentile
                )
                .padding(.top, 4)
            }
        }
        .onChange(of: selectedInterval, initial: true) {
            selectedDate = nil
            selectedPercentile = nil
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    private var boxplotChart: some View {
        let thresholds = StatChartUtils.glucoseThresholds(timeInRangeType: timeInRangeType, units: units)
        let seriesScale: [(label: String, color: Color)] = [
            ("0-100%", .blue.opacity(0.15)),
            ("10-90%", .blue.opacity(0.3)),
            ("25-75%", .blue.opacity(0.5)),
            ("Median", .blue)
        ] + thresholds.map { ($0.label, $0.color) }

        return Chart {
            ForEach(dailyStats) { day in
                let opacity = selectedDayStart.map { day.date == $0 ? 1 : 0.3 } ?? 1

                spacerBarMark(for: day)
                percentileBarMark(
                    for: day,
                    startValue: day.minimum.asUnit(units),
                    endValue: day.percentile10.asUnit(units),
                    rangeName: "0-100%",
                    opacity: opacity
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile10.asUnit(units),
                    endValue: day.percentile25.asUnit(units),
                    rangeName: "10-90%",
                    opacity: opacity
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile25.asUnit(units),
                    endValue: day.percentile75.asUnit(units),
                    rangeName: "25-75%",
                    opacity: opacity
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile75.asUnit(units),
                    endValue: day.percentile90.asUnit(units),
                    rangeName: "10-90%",
                    opacity: opacity
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile90.asUnit(units),
                    endValue: day.maximum.asUnit(units),
                    rangeName: "0-100%",
                    opacity: opacity
                )
                medianMark(for: day, opacity: opacity)
            }

            ForEach(thresholds, id: \.label) { threshold in
                RuleMark(y: .value("Limit", threshold.value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(by: .value("Range", threshold.label))
            }

            if let selectedPercentile = selectedPercentile {
                ForEach(dailyStats) { day in
                    LineMark(
                        x: .value("SelectedDate", day.date, unit: .day),
                        y: .value("SelectedValue", selectedPercentile.getValue(from: day).asUnit(units))
                    )
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: selectedInterval == .total ? 1 : 2))

                    PointMark(
                        x: .value("SelectedDate", day.date, unit: .day),
                        y: .value("SelectedValue", selectedPercentile.getValue(from: day).asUnit(units))
                    )
                    .symbolSize(selectedInterval == .total ? 10 : 30)
                    .foregroundStyle(Color.purple)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let glucoseValue = value.as(Double.self) {
                        Text(
                            units == .mmolL ?
                                glucoseValue.formatted(.number.precision(.fractionLength(1))) :
                                glucoseValue.formatted(.number.precision(.fractionLength(0)))
                        )
                        .font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            StatChartUtils.dateAxisMarks(for: selectedInterval)
        }
        .chartYScale(domain: glucoseYScaleDomain())
        .chartXSelection(value: $selectedDate)
        .onChange(of: selectedDate) { _, newValue in
            if newValue != nil {
                selectedPercentile = nil
            }
        }
        .chartForegroundStyleScale(
            domain: seriesScale.map(\.label),
            range: seriesScale.map(\.color)
        )
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: DateComponents(hour: 0),
                majorAlignment: .matching(
                    StatChartUtils.alignmentComponents(for: selectedInterval)
                )
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval, at: scrollPosition))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Daily glucose percentile chart"))
    }

    private func percentileBarMark(
        for day: GlucoseDailyPercentileStats,
        startValue: Double,
        endValue: Double,
        rangeName: String,
        opacity: Double
    ) -> some ChartContent {
        BarMark(
            x: .value("Day", day.date, unit: .day),
            y: .value("Percentage", endValue - startValue)
        )
        .foregroundStyle(by: .value("Range", rangeName))
        .opacity(opacity)
    }

    private func medianMark(for day: GlucoseDailyPercentileStats, opacity: Double) -> some ChartContent {
        let baseDate = Calendar.current.startOfDay(for: day.date)
        let startOffset = Int(0.15 * 24 * 60)
        let endOffset = Int(0.85 * 24 * 60)

        return RuleMark(
            xStart: .value("DayStart", Calendar.current.date(byAdding: .minute, value: startOffset, to: baseDate)!),
            xEnd: .value("DayEnd", Calendar.current.date(byAdding: .minute, value: endOffset, to: baseDate)!),
            y: .value("Median", day.median.asUnit(units))
        )
        .lineStyle(StrokeStyle(lineWidth: 2))
        .foregroundStyle(by: .value("Range", "Median"))
        .opacity(opacity)
    }

    private func spacerBarMark(for day: GlucoseDailyPercentileStats) -> some ChartContent {
        BarMark(
            x: .value("Day", day.date, unit: .day),
            y: .value("Percentage", day.minimum.asUnit(units))
        )
        .foregroundStyle(Color.clear)
    }

    private func glucoseYScaleDomain() -> ClosedRange<Double> {
        let padding = 20.0.asUnit(units)
        let bottomLimit = 40.0.asUnit(units)
        let topLimit = 400.0.asUnit(units)

        if visibleDailyStats.isEmpty {
            return bottomLimit ... topLimit
        }

        let maxValue = visibleDailyStats.lazy.map { $0.maximum.asUnit(units) }.max() ?? topLimit

        return bottomLimit ... max(Double(GlucoseBand.inRangeThreshold).asUnit(units), maxValue + padding)
    }
}
