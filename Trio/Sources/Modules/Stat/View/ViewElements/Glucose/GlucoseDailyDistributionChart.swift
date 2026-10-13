import Charts
import SwiftUI

struct GlucoseDailyDistributionChart: View {
    let highLimit: Decimal
    let units: GlucoseUnits
    let timeInRangeType: TimeInRangeType
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit

    let dailyStats: [GlucoseDailyDistributionStats]
    let readingsByDay: [Date: [GlucoseReading]]

    // Scrolling and selection states
    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    private var selectedDayStart: Date? {
        selectedDate.map { Calendar.current.startOfDay(for: $0) }
    }

    private var visibleGlucose: [GlucoseReading] {
        let calendar = Calendar.current
        let days = (0 ..< StatChartUtils.dayCount(for: selectedInterval)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: visibleDateRange.start)
        }
        return days.flatMap { readingsByDay[$0] ?? [] }
    }

    private var selectedDayGlucose: [GlucoseReading] {
        guard let selectedDayStart else { return [] }
        return readingsByDay[selectedDayStart, default: []]
    }

    // Computes the visible date range based on the current scroll position
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    // Active glucose data - either selected day or visible range
    private var activeGlucoseData: [GlucoseReading] {
        selectedDayStart != nil ? selectedDayGlucose : visibleGlucose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartView
                .frame(height: 200)

            // Date label with transition
            Text(selectedDate.map { StatChartUtils.formatDate($0) } ?? StatChartUtils.formatVisibleDateRange(
                from: visibleDateRange.start,
                to: visibleDateRange.end,
                for: selectedInterval
            ))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            // Single sector chart with data switching
            GlucoseSectorChart(
                highLimit: highLimit,
                units: units,
                glucose: activeGlucoseData,
                timeInRangeType: timeInRangeType,
                showChart: false
            )
            .equatable()

            Divider().padding(.vertical, 4)

            // Single metrics view with data switching
            GlucoseMetricsView(
                units: units,
                eA1cDisplayUnit: eA1cDisplayUnit,
                glucose: activeGlucoseData
            )
            .equatable()
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
        .onChange(of: selectedInterval) {
            selectedDate = nil
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    /// The main chart visualization showing glucose distribution by day
    private var chartView: some View {
        let bandInfos = GlucoseBand.allCases.map { band in
            (
                band: band,
                info: StatChartUtils
                    .glucoseBandDisplayInfo(for: band, units: units, timeInRangeType: timeInRangeType, highLimit: highLimit)
            )
        }

        return Chart {
            ForEach(dailyStats) { day in
                ForEach(bandInfos, id: \.band) { entry in
                    barMark(x: day, y: day.pct(for: entry.band), name: entry.info.label)
                }
            }
        }
        .chartForegroundStyleScale(
            domain: bandInfos.map(\.info.label),
            range: bandInfos.map { $0.info.color.opacity(0.8) }
        )
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartYScale(domain: 0 ... 100)
        .chartXAxis {
            StatChartUtils.dateAxisMarks(for: selectedInterval)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let percentage = value.as(Double.self) {
                    AxisValueLabel {
                        Text(StatChartUtils.formatPercentage(percentage, fractionDigits: 0))
                            .font(.footnote)
                    }
                    AxisGridLine()
                }
            }
        }
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
        .accessibilityLabel(Text("Daily glucose distribution chart"))
    }

    /// Creates a bar mark for the requested date and range
    private func barMark(x: GlucoseDailyDistributionStats, y: Double, name: String) -> some ChartContent {
        BarMark(
            x: .value("Date", x.date, unit: .day),
            y: .value("Percentage", y)
        )
        .foregroundStyle(by: .value("Range", name))
        .opacity(selectedDayStart.map { x.date == $0 ? 1 : 0.3 } ?? 1)
    }
}
