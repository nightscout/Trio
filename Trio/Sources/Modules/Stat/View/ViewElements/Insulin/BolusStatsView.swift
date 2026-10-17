import Charts
import SwiftUI

struct BolusStatsView: View {
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    let bolusStats: [BolusStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    private var headlineValues: (manual: Double, smb: Double, external: Double) {
        selectedInterval == .day
            ? state.calculateBolusTotals(for: visibleDateRange)
            : state.calculateBolusAverages(for: visibleDateRange)
    }

    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    private func getBolusForDate(_ date: Date) -> BolusStats? {
        bolusStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                StatChartUtils.statRow(
                    label: "Manual:",
                    value: headlineValues.manual,
                    unit: "U",
                    showAverageSymbol: selectedInterval != .day
                )
                StatChartUtils.statRow(
                    label: "SMB:",
                    value: headlineValues.smb,
                    unit: "U",
                    showAverageSymbol: selectedInterval != .day
                )
                StatChartUtils.statRow(
                    label: "External:",
                    value: headlineValues.external,
                    unit: "U",
                    showAverageSymbol: selectedInterval != .day
                )
                Divider()
                StatChartUtils.statRow(
                    label: "Total:",
                    value: headlineValues.manual + headlineValues.smb + headlineValues.external,
                    unit: "U",
                    showAverageSymbol: selectedInterval != .day
                )
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

            VStack(alignment: .trailing) {
                Text("Bolus Insulin (U)")
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

    private var chartsView: some View {
        Chart {
            ForEach(bolusStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.manualBolus)
                )
                .foregroundStyle(by: .value("Type", "Manual"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.smb)
                )
                .foregroundStyle(by: .value("Type", "SMB"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.external)
                )
                .foregroundStyle(by: .value("Type", "External"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
            }

            if selectedInterval == .day {
                StatChartUtils.fullDayDomainAnchor()
            }

            if let selectedDate, let selectedBolus = getBolusForDate(selectedDate)
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
                ) { _ in
                    StatSelectionPopover(
                        title: StatChartUtils.selectionTitle(for: selectedDate, showHourRange: selectedInterval == .day),
                        tint: .blue
                    ) {
                        let total = selectedBolus.manualBolus + selectedBolus.smb + selectedBolus.external
                        Grid(alignment: .leading) {
                            StatChartUtils.popoverRow(
                                label: "Manual:",
                                formattedValue: StatChartUtils.format(selectedBolus.manualBolus),
                                unit: "U"
                            )
                            StatChartUtils.popoverRow(
                                label: "SMB:",
                                formattedValue: StatChartUtils.format(selectedBolus.smb),
                                unit: "U"
                            )
                            StatChartUtils.popoverRow(
                                label: "External:",
                                formattedValue: StatChartUtils.format(selectedBolus.external),
                                unit: "U"
                            )
                            Divider()
                            StatChartUtils.popoverRow(
                                label: "Total:",
                                formattedValue: StatChartUtils.format(total),
                                unit: "U"
                            )
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "SMB": Color.blue,
            "Manual": Color.teal,
            "External": Color.purple
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
        .accessibilityLabel(Text("Bolus insulin bar chart"))
    }
}
