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
    let highLimit: Decimal
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
    private var aggregatedVisibleStats: GlucoseDailyPercentileStats? {
        let calendar = Calendar.current
        let days = (0 ..< StatChartUtils.dayCount(for: selectedInterval)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: visibleDateRange.start)
        }
        let values = days.flatMap { readingsByDay[$0, default: []] }.map { Double($0.value) }.sorted()
        guard !values.isEmpty else { return nil }

        return GlucoseDailyPercentileStats(
            date: visibleDateRange.start,
            minimum: values.first ?? 0,
            percentile10: StatChartUtils.percentile(0.10, of: values),
            percentile25: StatChartUtils.percentile(0.25, of: values),
            median: StatChartUtils.percentile(0.5, of: values),
            percentile75: StatChartUtils.percentile(0.75, of: values),
            percentile90: StatChartUtils.percentile(0.90, of: values),
            maximum: values.last ?? 0
        )
    }

    private var detailViewData: (data: GlucoseDailyPercentileStats, dateText: String)? {
        if let start = selectedDayStart {
            let data = selectedDateStats ?? GlucoseDailyPercentileStats(date: start)
            return (data, StatChartUtils.formatDate(start))
        }
        if let aggregatedData = aggregatedVisibleStats {
            return (aggregatedData, StatChartUtils.formatVisibleDateRange(
                from: visibleDateRange.start,
                to: visibleDateRange.end,
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
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
        .onChange(of: selectedInterval) {
            selectedDate = nil
            selectedPercentile = nil
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    private var boxplotChart: some View {
        let thresholds = StatChartUtils.glucoseThresholds(timeInRangeType: timeInRangeType, highLimit: highLimit, units: units)
        let seriesScale: [(label: String, color: Color)] = [
            ("0-100%", .blue.opacity(0.15)),
            ("10-90%", .blue.opacity(0.3)),
            ("25-75%", .blue.opacity(0.5)),
            ("Median", .blue)
        ] + thresholds.map { ($0.label, $0.color) }

        return Chart {
            ForEach(dailyStats) { day in
                spacerBarMark(for: day)
                percentileBarMark(
                    for: day,
                    startValue: day.minimum.asUnit(units),
                    endValue: day.percentile10.asUnit(units),
                    rangeName: "0-100%"
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile10.asUnit(units),
                    endValue: day.percentile25.asUnit(units),
                    rangeName: "10-90%"
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile25.asUnit(units),
                    endValue: day.percentile75.asUnit(units),
                    rangeName: "25-75%"
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile75.asUnit(units),
                    endValue: day.percentile90.asUnit(units),
                    rangeName: "10-90%"
                )
                percentileBarMark(
                    for: day,
                    startValue: day.percentile90.asUnit(units),
                    endValue: day.maximum.asUnit(units),
                    rangeName: "0-100%"
                )
            }

            ForEach(dailyStats) { day in
                medianMark(for: day)
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
        rangeName: String
    ) -> some ChartContent {
        BarMark(
            x: .value("Day", day.date, unit: .day),
            y: .value("Percentage", endValue - startValue)
        )
        .foregroundStyle(by: .value("Range", rangeName))
        .opacity(getOpacity(for: day))
    }

    private func medianMark(for day: GlucoseDailyPercentileStats) -> some ChartContent {
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
        .opacity(getOpacity(for: day))
    }

    private func getOpacity(for day: GlucoseDailyPercentileStats) -> Double {
        selectedDayStart.map { day.date == $0 ? 1 : 0.3 } ?? 1
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

        return bottomLimit ... max(Double(highLimit.asUnit(units)), maxValue + padding)
    }
}
