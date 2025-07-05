import Charts
import SwiftUI

enum GlucosePercentileType: String, Identifiable {
    case minimum = "Min"
    case percentile10 = "10th"
    case percentile25 = "25th"
    case median = "Median"
    case percentile75 = "75th"
    case percentile90 = "90th"
    case maximum = "Max"

    var id: String { rawValue }

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
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let units: GlucoseUnits
    let timeInRangeType: TimeInRangeType
    let selectedInterval: Stat.StateModel.StatsTimeInterval

    @Binding var isDaySelected: Bool

    // Scrolling and selection states
    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?
    @State private var updateTimer = Stat.UpdateTimer()
    @State private var visibleDailyStats: [GlucoseDailyPercentileStats] = []

    // State for selected percentile
    @State private var selectedPercentile: GlucosePercentileType?

    // State model for accessing the shared calculations
    let state: Stat.StateModel

    // Computes the visible date range based on the current scroll position
    @State private var visibleDateRange: (start: Date, end: Date) = (Date(), Date())

    private func calculateVisibleDailyStats() {
        let calendar = Calendar.current
        visibleDailyStats = state.dailyGlucosePercentileStats.filter { stat in
            let statDate = calendar.startOfDay(for: stat.date)
            return statDate >= calendar.startOfDay(for: visibleDateRange.start) &&
                statDate <= calendar.startOfDay(for: visibleDateRange.end)
        }
    }

    private func calculateVisibleDateRange() {
        visibleDateRange = StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    // Gets selected day stats
    private var selectedDateStats: GlucoseDailyPercentileStats? {
        selectedDate.flatMap { day in
            state.glucosePercentileCache[Calendar.current.startOfDay(for: day)]
        }
    }

    // Aggregates data from all visible days
    private var aggregatedVisibleStats: GlucoseDailyPercentileStats? {
        guard !visibleDailyStats.isEmpty else { return nil }

        // Collect all glucose values from visible days
        var allMinimums: [Double] = []
        var allMaximums: [Double] = []
        var all10thPercentiles: [Double] = []
        var all25thPercentiles: [Double] = []
        var allMedians: [Double] = []
        var all75thPercentiles: [Double] = []
        var all90thPercentiles: [Double] = []

        // Collect data from all visible days
        for stats in visibleDailyStats where stats.median > 0 {
            allMinimums.append(stats.minimum)
            allMaximums.append(stats.maximum)
            all10thPercentiles.append(stats.percentile10)
            all25thPercentiles.append(stats.percentile25)
            allMedians.append(stats.median)
            all75thPercentiles.append(stats.percentile75)
            all90thPercentiles.append(stats.percentile90)
        }

        // Calculate aggregated values
        let aggMinimum = allMinimums.min() ?? 0
        let aggMaximum = allMaximums.max() ?? 0
        let aggP10 = StatChartUtils.medianCalculationDouble(array: all10thPercentiles)
        let aggP25 = StatChartUtils.medianCalculationDouble(array: all25thPercentiles)
        let aggMedian = StatChartUtils.medianCalculationDouble(array: allMedians)
        let aggP75 = StatChartUtils.medianCalculationDouble(array: all75thPercentiles)
        let aggP90 = StatChartUtils.medianCalculationDouble(array: all90thPercentiles)

        // Create a new stats object with the visible date range and aggregated values
        return GlucoseDailyPercentileStats(
            date: visibleDateRange.start,
            readings: [], // Empty array since this is aggregated data
            minimum: aggMinimum,
            percentile10: aggP10,
            percentile25: aggP25,
            median: aggMedian,
            percentile75: aggP75,
            percentile90: aggP90,
            maximum: aggMaximum
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
            return (selectedData, selectedData.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
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
            calculateVisibleDateRange()
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
            calculateVisibleDailyStats()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                calculateVisibleDateRange()
                calculateVisibleDailyStats()
            }
        }
        .onChange(of: selectedInterval) { _, _ in
            selectedDate = nil
            selectedPercentile = nil
            isDaySelected = false
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    // Simple boxplot chart with improved visuals - broken down into components
    private var boxplotChart: some View {
        Chart {
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
                        .zIndex(200) // Set very high z-index

                        // Point marks
                        PointMark(
                            x: .value("SelectedDate", day.date, unit: .day),
                            y: .value("SelectedValue", selectedPercentile.getValue(from: day).asUnit(units))
                        )
                        .symbolSize(selectedInterval == .total ? 10 : 30)
                        .foregroundStyle(Color.purple)
                        .zIndex(300) // Even higher z-index for points
                    }
                }
            }

            // Threshold lines
            RuleMark(
                y: .value("Low Limit", Double(timeInRangeType.bottomThreshold).asUnit(units))
            )
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(by: .value("Range", "\(timeInRangeType.bottomThreshold.formatted(withUnits: units))"))
            .zIndex(100)

            RuleMark(
                y: .value("Mid Limit", Double(timeInRangeType.topThreshold).asUnit(units))
            )
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(by: .value("Range", "\(timeInRangeType.topThreshold.formatted(withUnits: units))"))
            .zIndex(100)

            RuleMark(
                y: .value("High Limit", Double(highLimit.asUnit(units)))
            )
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(by: .value("Range", "\(highLimit.formatted(withUnits: units))"))
            .zIndex(100)
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
            AxisMarks(preset: .aligned, values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    let calendar = Calendar.current

                    switch selectedInterval {
                    case .month:
                        // Mark the first day of the week
                        let weekday = calendar.component(.weekday, from: date)
                        if weekday == calendar.firstWeekday {
                            AxisValueLabel(format: .dateTime.day(), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .total:
                        // Mark the start of the month
                        let day = calendar.component(.day, from: date)
                        if day == 1 {
                            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    default:
                        // Mark every day
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                            .font(.footnote)
                        AxisGridLine()
                    }
                }
            }
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
        .chartForegroundStyleScale([
            "0-100%": .blue.opacity(0.15),
            "10-90%": .blue.opacity(0.3),
            "25-75%": .blue.opacity(0.5),
            "Median": .blue,
            "\(timeInRangeType.bottomThreshold.formatted(withUnits: units))": .red,
            "\(timeInRangeType.topThreshold.formatted(withUnits: units))": .mint,
            "\(highLimit.formatted(withUnits: units))": .orange
        ])
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
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval))
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
        selectedDate.map { date in
            StatChartUtils.isSameTimeUnit(day.date, date, for: .total) ? 1 : 0.3
        } ?? 1
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
        // Find actual min/max from data
        if visibleDailyStats.isEmpty {
            return 0 ... (units == .mgdL ? 250 : 14.0)
        }

        var allValues: [Double] = []
        for day in visibleDailyStats where day.minimum > 0 {
            allValues.append(day.minimum.asUnit(units))
            allValues.append(day.maximum.asUnit(units))
        }

        guard !allValues.isEmpty else {
            return 0 ... (units == .mgdL ? 250 : 14.0)
        }

        let minValue = allValues.min() ?? 0
        let maxValue = allValues.max() ?? (units == .mgdL ? 250 : 14.0)

        // Add some padding
        let padding = units == .mgdL ? 20.0 : 1.0
        return max(0, minValue - padding) ... maxValue + padding
    }
}
