import Charts
import SwiftUI

/// A view that displays a bar chart for Total Daily Dose (TDD) statistics.
///
/// This view presents insulin usage over time, with the ability to adjust the time interval
/// and scroll through historical data.
struct TotalDailyDoseChart: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    /// The list of TDD statistics data.
    let tddStats: [TDDStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?

    private var headlineValues: Double {
        selectedInterval == .day
            ? state.calculateTDDTotals(for: visibleDateRange)
            : state.calculateTDDAverages(for: visibleDateRange)
    }

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// Retrieves the TDD statistic for a given date.
    /// - Parameter date: The date for which to retrieve TDD data.
    /// - Returns: The `TDDStats` object if available, otherwise `nil`.
    private func getTDDForDate(_ date: Date) -> TDDStats? {
        tddStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Total Daily Dose (U)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chartsView
            }
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
        .onChange(of: selectedInterval) {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    /// A view displaying the statistics summary including average TDD.
    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                StatChartUtils.statRow(
                    label: selectedInterval == .day ? "Total:" : "Average:",
                    value: headlineValues,
                    unit: "U",
                    showAverageSymbol: false
                )
            }
            .font(.headline)
            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedInterval)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// A view displaying the bar chart for TDD statistics.
    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(Color.insulin)
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate,
               let selectedTDD = getTDDForDate(selectedDate)
            {
                RuleMark(
                    x: .value("Selected Date", selectedDate)
                )
                .foregroundStyle(Color.insulin.opacity(0.5))
                .annotation(
                    position: .top,
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    StatSelectionPopover(
                        selectedDate: selectedDate,
                        selectedInterval: selectedInterval,
                        tint: .blue
                    ) {
                        Divider()

                        HStack {
                            Text(selectedTDD.amount.formatted(.number.precision(.fractionLength(1))))
                            Text("U").foregroundStyle(Color.secondary)
                        }
                        .font(.headline)
                    }
                }
            }

            // Dummy PointMark to force SwiftCharts to render a visible domain of 00:00-23:59
            // i.e. single day from midnight to midnight
            if selectedInterval == .day {
                StatChartUtils.fullDayDomainAnchor()
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(amount.formatted(.number.precision(.fractionLength(0))))
                            .font(.footnote)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartXAxis {
            StatChartUtils.dateAxisMarks(for: selectedInterval)
        }
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: DateComponents(hour: 0),
                majorAlignment: .matching(StatChartUtils.alignmentComponents(for: selectedInterval))
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval, at: scrollPosition))
        .frame(height: 250)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Total daily dose bar chart"))
    }
}
