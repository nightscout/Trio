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

    // Function to get the percentile value from a stats object
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

    // State model for accessing the shared calculations
    let state: Stat.StateModel

    @Binding var isDaySelected: Bool

    // Scrolling and selection states
    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    // State for selected percentile
    @State private var selectedPercentile: GlucosePercentileType?

    private var visibleDailyStats: [GlucoseDailyPercentileStats] {
        state.dailyGlucosePercentileStats.filter { stat in
            StatChartUtils.isStatInRange(stat.date, in: visibleDateRange)
        }
    }

    // Computes the visible date range based on the current scroll position
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    // Gets selected day stats
    private var selectedDateStats: GlucoseDailyPercentileStats? {
        selectedDate.flatMap { day in
            state.dailyGlucosePercentileStats.first {
                Calendar.current.isDate($0.date, inSameDayAs: day)
            }
        }
    }

    // Aggregates data from all visible days
    private var aggregatedVisibleStats: GlucoseDailyPercentileStats? {
        let rows = visibleDailyStats.filter { $0.median > 0 }
        guard !rows.isEmpty else { return nil }

        return GlucoseDailyPercentileStats(
            date: visibleDateRange.start,
            minimum: rows.map(\.minimum).min() ?? 0,
            percentile10: StatChartUtils.medianCalculationDouble(array: rows.map(\.percentile10)),
            percentile25: StatChartUtils.medianCalculationDouble(array: rows.map(\.percentile25)),
            median: StatChartUtils.medianCalculationDouble(array: rows.map(\.median)),
            percentile75: StatChartUtils.medianCalculationDouble(array: rows.map(\.percentile75)),
            percentile90: StatChartUtils.medianCalculationDouble(array: rows.map(\.percentile90)),
            maximum: rows.map(\.maximum).max() ?? 0
        )
    }

    // Format a single date for display
    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    // Get the appropriate detail view data
    private var detailViewData: (data: GlucoseDailyPercentileStats, dateText: String)? {
        if let selectedData = selectedDateStats {
            // Case 1: Selected specific day
            return (selectedData, formatDate(selectedData.date))
        } else if let aggregatedData = aggregatedVisibleStats {
            // Case 2: Using aggregated data
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

            // Display detail view if we have data
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
            isDaySelected = false
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    // Simple boxplot chart with improved visuals - broken down into components
    private var boxplotChart: some View {
        let thresholds = StatChartUtils.glucoseThresholds(timeInRangeType: timeInRangeType, highLimit: highLimit, units: units)
        let seriesScale: [(label: String, color: Color)] = [
            ("0-100%", .blue.opacity(0.15)),
            ("10-90%", .blue.opacity(0.3)),
            ("25-75%", .blue.opacity(0.5)),
            ("Median", .blue)
        ] + thresholds.map { ($0.label, $0.color) }

        return Chart {
            // First draw all the non-interactive elements
            ForEach(state.dailyGlucosePercentileStats) { day in
                if day.maximum > 0 { // Check if we have valid data
                    // Add background components for each day
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
            }

            // Draw median marks - these should appear above the percentile bars but below the selected percentile
            ForEach(state.dailyGlucosePercentileStats) { day in
                if day.maximum > 0 {
                    medianMark(for: day)
                }
            }

            ForEach(thresholds, id: \.label) { threshold in
                RuleMark(y: .value("Limit", threshold.value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(by: .value("Range", threshold.label))
            }

            // Draw the selected percentile elements LAST so they're on top
            if let selectedPercentile = selectedPercentile {
                ForEach(state.dailyGlucosePercentileStats) { day in
                    if day.maximum > 0 {
                        // Line connecting points
                        LineMark(
                            x: .value("SelectedDate", day.date, unit: .day),
                            y: .value("SelectedValue", selectedPercentile.getValue(from: day).asUnit(units))
                        )
                        .foregroundStyle(Color.purple)
                        .lineStyle(StrokeStyle(lineWidth: selectedInterval == .total ? 1 : 2))

                        // Point marks
                        PointMark(
                            x: .value("SelectedDate", day.date, unit: .day),
                            y: .value("SelectedValue", selectedPercentile.getValue(from: day).asUnit(units))
                        )
                        .symbolSize(selectedInterval == .total ? 10 : 30)
                        .foregroundStyle(Color.purple)
                    }
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
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .onChange(of: selectedDate) { _, newValue in
            isDaySelected = newValue != nil
            // Clear percentile selection when a day is selected
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

    // MARK: - Chart Components

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

    // Median mark - a horizontal line at the median point
    private func medianMark(for day: GlucoseDailyPercentileStats) -> some ChartContent {
        let baseDate = Calendar.current.startOfDay(for: day.date)
        let startOffset = Int(0.15 * 24 * 60) // 15% of minutes in a day
        let endOffset = Int(0.85 * 24 * 60) // 85% of minutes in a day

        return RuleMark(
            xStart: .value("DayStart", Calendar.current.date(byAdding: .minute, value: startOffset, to: baseDate)!),
            xEnd: .value("DayEnd", Calendar.current.date(byAdding: .minute, value: endOffset, to: baseDate)!),
            y: .value("Median", day.median.asUnit(units))
        )
        .lineStyle(StrokeStyle(lineWidth: 2))
        .foregroundStyle(by: .value("Range", "Median"))
        .opacity(getOpacity(for: day))
    }

    // Helper function to determine opacity based on selections
    private func getOpacity(for day: GlucoseDailyPercentileStats) -> Double {
        selectedDate.map { Calendar.current.isDate(day.date, inSameDayAs: $0) ? 1 : 0.3 } ?? 1
    }

    // Spacer box for each day
    private func spacerBarMark(for day: GlucoseDailyPercentileStats) -> some ChartContent {
        BarMark(
            x: .value("Day", day.date, unit: .day),
            y: .value("Percentage", day.minimum.asUnit(units))
        )
        .foregroundStyle(Color.clear)
    }

    // Calculate an appropriate Y axis domain for the chart
    private func glucoseYScaleDomain() -> ClosedRange<Double> {
        let padding = 20.0.asUnit(units)
        let bottomLimit = 40.0.asUnit(units)
        let topLimit = 400.0.asUnit(units)

        if visibleDailyStats.isEmpty {
            return bottomLimit ... topLimit
        }

        let maxValue = visibleDailyStats.lazy.filter { $0.minimum > 0 }.map { $0.maximum.asUnit(units) }.max() ?? topLimit

        return bottomLimit ... max(Double(highLimit.asUnit(units)), maxValue + padding)
    }
}
