import Charts
import SwiftUI

/// A view that displays a bar chart for bolus insulin statistics.
///
/// This view presents different types of bolus insulin (manual, SMB, and external) over time,
/// allowing users to adjust the time interval and scroll through historical data.
struct BolusStatsView: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    /// The list of bolus statistics data.
    let bolusStats: [BolusStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?

    private var headlineValues: (manual: Double, smb: Double, external: Double) {
        selectedInterval == .day
            ? state.calculateBolusTotals(for: visibleDateRange)
            : state.calculateBolusAverages(for: visibleDateRange)
    }

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// Retrieves the bolus statistic for a given date.
    /// - Parameter date: The date for which to retrieve bolus data.
    /// - Returns: The `BolusStats` object if available, otherwise `nil`.
    private func getBolusForDate(_ date: Date) -> BolusStats? {
        bolusStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// A view displaying the statistics summary including bolus insulin averages.
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

    /// A view displaying the bar chart for bolus insulin statistics.
    private var chartsView: some View {
        Chart {
            ForEach(bolusStats) { stat in
                // Total Bolus Bar
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

                // Carb Bolus Bar
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
                // Correction Bolus Bar
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

            // Dummy PointMark to force SwiftCharts to render a visible domain of 00:00-23:59
            // i.e. single day from midnight to midnight
            if selectedInterval == .day {
                StatChartUtils.fullDayDomainAnchor()
            }

            // Selection popover outside of the ForEach loop!
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
                        selectedDate: selectedDate,
                        selectedInterval: selectedInterval,
                        tint: .blue
                    ) {
                        Divider()
                        Grid(alignment: .leading) {
                            StatChartUtils.popoverRow(label: "Manual:", value: selectedBolus.manualBolus, unit: "U")
                            StatChartUtils.popoverRow(label: "SMB:", value: selectedBolus.smb, unit: "U")
                            StatChartUtils.popoverRow(label: "External:", value: selectedBolus.external, unit: "U")
                            Divider()
                            StatChartUtils.popoverRow(
                                label: "Total:",
                                value: selectedBolus.manualBolus + selectedBolus.smb + selectedBolus.external,
                                unit: "U"
                            )
                        }.font(.headline)
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "SMB": Color.blue,
            "Manual": Color.teal,
            "External": Color.purple
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = [
                (String(localized: "SMB"), Color.blue),
                (String(localized: "Manual"), Color.teal),
                (String(localized: "External"), Color.purple)
            ]

            let columns = [GridItem(.adaptive(minimum: 65), spacing: 4)]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(legendItems, id: \.0) { item in
                    StatChartUtils.legendItem(label: item.0, color: item.1)
                }
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
        .accessibilityLabel(Text("Bolus insulin bar chart"))
    }
}
