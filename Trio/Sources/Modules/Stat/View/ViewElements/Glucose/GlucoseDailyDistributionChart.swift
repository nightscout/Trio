import Charts
import SwiftUI

struct GlucoseDailyDistributionChart: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let units: GlucoseUnits
    let timeInRangeType: TimeInRangeType
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit

    @Binding var isDaySelected: Bool

    // Scrolling and selection states
    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?
    @State private var updateTimer = Stat.UpdateTimer()
    @State private var visibleGlucose: [GlucoseStored] = []

    // State model for accessing the shared data
    let state: Stat.StateModel

    // Computes the visible date range based on the current scroll position
    @State private var visibleDateRange: (start: Date, end: Date) = (Date(), Date())

    // Gets daily distribution stats for the visible date range
    private var visibleDailyStats: [GlucoseDailyDistributionStats] {
        let calendar = Calendar.current
        return state.dailyGlucoseDistributionStats.filter { stat in
            let statDate = calendar.startOfDay(for: stat.date)
            return statDate >= calendar.startOfDay(for: visibleDateRange.start) &&
                statDate <= calendar.startOfDay(for: visibleDateRange.end)
        }
    }

    private func calculateVisibleDateRange() {
        visibleDateRange = StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    // Gets selected day stats
    private var selectedDateStats: GlucoseDailyDistributionStats? {
        guard let selectedDate = selectedDate else { return nil }
        let calendar = Calendar.current
        let startOfSelectedDate = calendar.startOfDay(for: selectedDate)
        return state.glucoseDistributionCache[startOfSelectedDate]
    }

    private func calculateVisibleGlucose() {
        let calendar = Calendar.current
        visibleGlucose = glucose.filter { reading in
            guard let date = reading.date else { return false }
            return date >= calendar.startOfDay(for: visibleDateRange.start) &&
                date <= calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: visibleDateRange.end))!
        }
    }

    // Compute selected day glucose readings
    private var selectedDateGlucose: [GlucoseStored] {
        guard let selectedDate = selectedDate else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        return glucose.filter { reading in
            guard let date = reading.date else { return false }
            return date >= dayStart && date < dayEnd
        }
    }

    // Active glucose data - either selected day or visible range
    private var activeGlucoseData: [GlucoseStored] {
        selectedDate != nil ? selectedDateGlucose : visibleGlucose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartView
                .frame(height: 200)

            // Date label with transition
            Text(selectedDate.map { formattedDate(for: $0) } ?? StatChartUtils.formatVisibleDateRange(
                from: visibleDateRange.start,
                to: visibleDateRange.end,
                for: selectedInterval
            ))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
                .animation(.easeInOut, value: selectedDate)

            // Single sector chart with data switching
            GlucoseSectorChart(
                highLimit: highLimit,
                units: units,
                glucose: activeGlucoseData,
                timeInRangeType: timeInRangeType,
                showChart: false
            )
            .animation(.easeInOut, value: selectedDate)

            Divider().padding(.vertical, 4)

            // Single metrics view with data switching
            GlucoseMetricsView(
                units: units,
                eA1cDisplayUnit: eA1cDisplayUnit,
                glucose: activeGlucoseData
            )
            .animation(.easeInOut, value: selectedDate)
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
            calculateVisibleDateRange()
            calculateVisibleGlucose()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                calculateVisibleDateRange()
                calculateVisibleGlucose()
            }
        }
        .onChange(of: selectedInterval) { _, _ in
            selectedDate = nil
            isDaySelected = false
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    /// Formatted date string for display
    private func formattedDate(for date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        return dateFormatter.string(from: date)
    }

    /// The main chart visualization showing glucose distribution by day
    private var chartView: some View {
        Chart {
            ForEach(state.dailyGlucoseDistributionStats) { day in
                barMark(x: day, y: day.veryLowPct, rangeName: "veryLow")
                barMark(x: day, y: day.lowPct, rangeName: "low")
                barMark(x: day, y: day.inSmallRangePct, rangeName: "inSmallRange")
                barMark(x: day, y: day.inRangePct - day.inSmallRangePct, rangeName: "inRange")
                barMark(x: day, y: day.highPct, rangeName: "high")
                barMark(x: day, y: day.veryHighPct, rangeName: "veryHigh")
            }
        }
        .chartForegroundStyleScale([
            legend("veryLow"): .purple,
            legend("low"): .red,
            legend("inSmallRange"): .green,
            legend("inRange"): .darkGreen,
            legend("high"): .loopYellow,
            legend("veryHigh"): .orange
        ])
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .onChange(of: selectedDate) { _, newValue in
            withAnimation(.easeInOut) {
                isDaySelected = newValue != nil
            }
        }
        .chartYScale(domain: 0 ... 100)
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
        .chartYAxis {
            AxisMarks(position: .trailing, values: [4, 25, 50, 75, 100]) { value in
                if let percentage = value.as(Double.self) {
                    AxisValueLabel {
                        Text((percentage / 100).formatted(.percent.precision(.fractionLength(0))))
                            .font(.footnote)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartYAxisLabel(alignment: .trailing) {
            Text("Percentage")
                .foregroundStyle(.primary)
                .font(.footnote)
                .padding(.vertical, 3)
        }
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollPosition.animation(.easeInOut))
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

    /// Formats a short string with the glucose values of the requested range.
    private func legend(_ rangeName: String) -> String {
        switch rangeName {
        case "veryLow":
            return "<\(Decimal(54).formatted(for: units))"
        case "low":
            return "\(Decimal(54).formatted(for: units))-\(Decimal(timeInRangeType.bottomThreshold - 1).formatted(for: units))"
        case "inSmallRange":
            return "\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units))-\(Decimal(timeInRangeType.topThreshold).formatted(for: units))"
        case "inRange":
            return "\(Decimal(timeInRangeType.topThreshold + 1).formatted(for: units))-\(highLimit.formatted(for: units))"
        case "high":
            return "\((highLimit + 1).formatted(for: units))-\(Decimal(250).formatted(for: units))"
        case "veryHigh":
            return ">\(Decimal(250).formatted(for: units))"
        default:
            return "error"
        }
    }

    /// Creates a bar mark for the requested date and range
    private func barMark(x: GlucoseDailyDistributionStats, y: Double, rangeName: String) -> some ChartContent {
        BarMark(
            x: .value("Date", x.date, unit: .day),
            y: .value("Percentage", y)
        )
        .foregroundStyle(by: .value("Range", legend(rangeName)))
        .opacity(selectedDate == nil || Calendar.current.isDate(selectedDate!, inSameDayAs: x.date) ? 1 : 0.3)
    }
}
