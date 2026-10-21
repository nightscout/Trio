import Charts
import SwiftUI

struct TotalDailyDoseChart: View {
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let tddStats: [TDDStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

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
        .onChange(of: selectedInterval, initial: true) {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
        }
    }

    private var statsView: some View {
        let range = visibleDateRange
        let headline = state.calculateTDDStats(for: range)

        return HStack {
            Grid(alignment: .leading) {
                StatChartUtils.statRow(
                    label: selectedInterval == .day ? "Total:" : "Average:",
                    value: headline,
                    unit: "U",
                    showAverageSymbol: false
                )
            }
            .font(.headline)
            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: range.start, to: range.end, for: selectedInterval)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                let opacity = selectedDate.map { date in
                    StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                } ?? 1
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(Color.insulin)
                .opacity(opacity)
            }

            if let selectedDate,
               let selectedTDD = getTDDForDate(selectedDate)
            {
                RuleMark(
                    x: .value("Selected Date", selectedDate)
                )
                .foregroundStyle(Color.insulin.opacity(0.5))
                .annotation(
                    position: .top,
                    alignment: StatChartUtils.popoverAlignment(
                        for: selectedDate,
                        scrollPosition: scrollPosition,
                        in: selectedInterval
                    ),
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                ) {
                    StatSelectionPopover(
                        title: StatChartUtils.selectionTitle(for: selectedDate, showHourRange: selectedInterval == .day),
                        tint: .blue
                    ) {
                        Grid(alignment: .leading) {
                            StatChartUtils.popoverRow(
                                label: "Amount:",
                                formattedValue: StatChartUtils.format(selectedTDD.amount),
                                unit: "U"
                            )
                        }
                    }
                }
            }

            if selectedInterval == .day {
                StatChartUtils.fullDayDomainAnchor()
            }
        }
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
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate)
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
