import Charts
import SwiftUI

struct LoopBarChartView: View {
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let loopStats: [LoopingStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    private func loop(for date: Date) -> LoopingStats? {
        loopStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    private var statsView: some View {
        let range = visibleDateRange
        let headline = state.calculateLoopStats(for: range)

        return HStack {
            Grid(alignment: .leading) {
                StatChartUtils.statRow(
                    label: "Successful:",
                    value: headline.successful,
                    showAverageSymbol: selectedInterval != .day,
                    fractionLength: selectedInterval != .day ? 1 : 0
                )
                StatChartUtils.statRow(
                    label: "Failed:",
                    value: headline.failed,
                    showAverageSymbol: selectedInterval != .day,
                    fractionLength: selectedInterval != .day ? 1 : 0
                )
                Divider()
                GridRow {
                    Text("Success rate:")
                    Text(StatChartUtils.formatPercentage(headline.successRate))
                }
                GridRow {
                    Text("Coverage:")
                    Text(StatChartUtils.formatPercentage(headline.coverage))
                }
            }
            .font(.headline)
            .accessibilityElement(children: .combine)

            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: range.start, to: range.end, for: selectedInterval)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)
            chartsView
            Divider()
            Text(
                "Success rate is the share of attempted loops that succeeded. Coverage is successful loops out of expected 5-minute cycles."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .onChange(of: selectedInterval, initial: true) {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    private var chartsView: some View {
        Chart {
            ForEach(loopStats) { stat in
                let opacity = selectedDate.map { date in
                    StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                } ?? 1

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.successful)
                )
                .foregroundStyle(by: .value("Type", "Successful"))
                .position(by: .value("Type", "Loops"))
                .opacity(opacity)

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.failed)
                )
                .foregroundStyle(by: .value("Type", "Failed"))
                .position(by: .value("Type", "Loops"))
                .opacity(opacity)
            }

            if selectedInterval == .day {
                StatChartUtils.fullDayDomainAnchor()
            }

            if let selectedDate, let selectedLoop = loop(for: selectedDate)
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
                        title: StatChartUtils.selectionTitle(for: selectedDate, showHourRange: selectedInterval == .day),
                        tint: .gray
                    ) {
                        Grid(alignment: .leading) {
                            StatChartUtils.popoverRow(
                                label: "Successful:",
                                formattedValue: StatChartUtils.format(Double(selectedLoop.successful), fractionLength: 0)
                            )
                            StatChartUtils.popoverRow(
                                label: "Failed:",
                                formattedValue: StatChartUtils.format(Double(selectedLoop.failed), fractionLength: 0)
                            )
                            StatChartUtils.popoverRow(
                                label: "Median duration:",
                                formattedValue: StatChartUtils.format(selectedLoop.medianDuration * 60),
                                unit: "s"
                            )
                            StatChartUtils.popoverRow(
                                label: "Median interval:",
                                formattedValue: StatChartUtils.format(selectedLoop.medianInterval),
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
                        Text(StatChartUtils.format(amount, fractionLength: 0))
                            .font(.footnote)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartXAxis {
            StatChartUtils.dateAxisMarks(for: selectedInterval)
        }
        .chartXSelection(value: $selectedDate)
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
