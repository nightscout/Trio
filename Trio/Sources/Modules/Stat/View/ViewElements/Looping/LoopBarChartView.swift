import Charts
import SwiftUI

struct LoopBarChartView: View {
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    let loopStats: [LoopingStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    private var headlineValues: (successful: Double, failed: Double, successRate: Double) {
        selectedInterval == .day
            ? state.calculateLoopTotals(for: visibleDateRange)
            : state.calculateLoopAverages(for: visibleDateRange)
    }

    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    private func getLoopForDate(_ date: Date) -> LoopingStats? {
        loopStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                StatChartUtils.statRow(
                    label: "Successful:",
                    value: headlineValues.successful,
                    showAverageSymbol: selectedInterval != .day,
                    fractionLength: selectedInterval != .day ? 1 : 0
                )
                StatChartUtils.statRow(
                    label: "Failed:",
                    value: headlineValues.failed,
                    showAverageSymbol: selectedInterval != .day,
                    fractionLength: selectedInterval != .day ? 1 : 0
                )
                Divider()
                StatChartUtils.statRow(
                    label: "Total:",
                    value: headlineValues.successful + headlineValues.failed,
                    showAverageSymbol: selectedInterval != .day,
                    fractionLength: selectedInterval != .day ? 1 : 0
                )
                GridRow {
                    Text("Success rate:")
                    Text(StatChartUtils.formatPercentage(headlineValues.successRate))
                }
            }
            .font(.headline)
            .accessibilityElement(children: .combine)

            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedInterval)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)
            chartsView
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
        .onChange(of: selectedInterval) {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    private var chartsView: some View {
        Chart {
            ForEach(loopStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.successful)
                )
                .foregroundStyle(by: .value("Type", "Successful"))
                .position(by: .value("Type", "Loops"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.failed)
                )
                .foregroundStyle(by: .value("Type", "Failed"))
                .position(by: .value("Type", "Loops"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Dummy PointMark to force SwiftCharts to render a visible domain of 00:00-23:59
            // i.e. single day from midnight to midnight
            if selectedInterval == .day {
                StatChartUtils.fullDayDomainAnchor()
            }

            if let selectedDate, let selectedLoop = getLoopForDate(selectedDate)
            {
                RuleMark(
                    x: .value("Selected Date", selectedDate)
                )
                .foregroundStyle(Color.gray.opacity(0.5))
                .annotation(
                    position: .top,
                    alignment: StatChartUtils.popoverAlignment(
                        for: selectedDate,
                        scrollPosition: scrollPosition,
                        in: selectedInterval
                    ),
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                ) { _ in
                    StatSelectionPopover(
                        selectedDate: selectedDate,
                        selectedInterval: selectedInterval,
                        tint: .gray
                    ) {
                        Grid(alignment: .leading) {
                            StatChartUtils.popoverRow(
                                label: "Successful:",
                                value: Double(selectedLoop.successful),
                                fractionLength: 0
                            )
                            StatChartUtils.popoverRow(label: "Failed:", value: Double(selectedLoop.failed), fractionLength: 0)
                            StatChartUtils.popoverRow(
                                label: "Median duration:",
                                value: selectedLoop.medianDuration * 60,
                                unit: "s"
                            )
                            StatChartUtils.popoverRow(
                                label: "Median interval:",
                                value: selectedLoop.medianInterval,
                                unit: "m"
                            )
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "Successful": Color.loopGreen,
            "Failed": Color.loopRed
        ])
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
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
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
        .frame(height: 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Successful and failed loops chart"))
    }
}
