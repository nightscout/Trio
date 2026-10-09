import Charts
import SwiftUI

struct GlucoseDailyDistributionChart: View {
    let highLimit: Decimal
    let units: GlucoseUnits
    let timeInRangeType: TimeInRangeType
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit

    // State model for accessing the shared data
    let state: Stat.StateModel

    @Binding var isDaySelected: Bool

    // Scrolling and selection states
    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    private var visibleGlucose: [GlucoseReading] {
        let calendar = Calendar.current
        let days = (0 ..< StatChartUtils.dayCount(for: selectedInterval)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: visibleDateRange.start)
        }
        return days.flatMap { state.glucoseReadingsByDay[$0] ?? [] }
    }

    private var selectedDayGlucose: [GlucoseReading] {
        guard let selectedDate else { return [] }
        return state.glucoseReadingsByDay[Calendar.current.startOfDay(for: selectedDate), default: []]
    }

    // Computes the visible date range based on the current scroll position
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    // Active glucose data - either selected day or visible range
    private var activeGlucoseData: [GlucoseReading] {
        selectedDate != nil ? selectedDayGlucose : visibleGlucose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartView
                .frame(height: 200)

            // Date label with transition
            Text(selectedDate.map { formatDate($0) } ?? StatChartUtils.formatVisibleDateRange(
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
            .equatable()
            .animation(.easeInOut, value: selectedDate)

            Divider().padding(.vertical, 4)

            // Single metrics view with data switching
            GlucoseMetricsView(
                units: units,
                eA1cDisplayUnit: eA1cDisplayUnit,
                glucose: activeGlucoseData
            )
            .equatable()
            .animation(.easeInOut, value: selectedDate)
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
        .onChange(of: selectedInterval) {
            selectedDate = nil
            isDaySelected = false
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// The main chart visualization showing glucose distribution by day
    private var chartView: some View {
        let infoFor: (GlucoseBand) -> (label: String, color: Color) = {
            StatChartUtils.glucoseBandDisplayInfo(for: $0, units: units, timeInRangeType: timeInRangeType, highLimit: highLimit)
        }

        let bands = GlucoseBand.allCases

        return Chart {
            ForEach(state.dailyGlucoseDistributionStats) { day in
                ForEach(bands, id: \.self) { entry in
                    barMark(x: day, y: day.pct(for: entry), name: infoFor(entry).label)
                }
            }
        }
        .chartForegroundStyleScale(
            domain: bands.map { infoFor($0).label },
            range: bands.map { infoFor($0).color.opacity(0.8) }
        )
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .onChange(of: selectedDate) { _, newValue in
            withAnimation(.easeInOut) {
                isDaySelected = newValue != nil
            }
        }
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
        .chartScrollPosition(x: $scrollPosition.animation(.easeInOut))
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
        .opacity(selectedDate.map { Calendar.current.isDate(x.date, inSameDayAs: $0) ? 1 : 0.3 } ?? 1)
    }
}
