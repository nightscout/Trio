import Charts
import SwiftUI

/// A view that displays a bar chart for meal statistics.
///
/// This view presents macronutrient intake (carbohydrates, fats, and proteins) over time,
/// allowing users to adjust the time interval and scroll through historical data.
struct MealStatsView: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    /// The list of meal statistics data.
    let mealStats: [MealStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?

    private var headlineValues: (carbs: Double, fat: Double, protein: Double) {
        selectedInterval == .day
            ? state.calculateMealTotals(for: visibleDateRange)
            : state.calculateMealAverages(for: visibleDateRange)
    }

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// Retrieves the meal statistic for a given date.
    /// - Parameter date: The date for which to retrieve meal data.
    /// - Returns: The `MealStats` object if available, otherwise `nil`.
    private func getMealForDate(_ date: Date) -> MealStats? {
        mealStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// A view displaying the statistics summary including macronutrient averages.
    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                StatChartUtils.statRow(
                    label: "Carbs:",
                    value: headlineValues.carbs,
                    unit: "g",
                    showAverageSymbol: selectedInterval != .day
                )
                if state.useFPUconversion {
                    StatChartUtils.statRow(
                        label: "Fat:",
                        value: headlineValues.fat,
                        unit: "g",
                        showAverageSymbol: selectedInterval != .day
                    )
                    StatChartUtils.statRow(
                        label: "Protein:",
                        value: headlineValues.protein,
                        unit: "g",
                        showAverageSymbol: selectedInterval != .day
                    )
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

            VStack(alignment: .trailing) {
                Text("Macro Nutrients (g)")
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

    /// A view displaying the bar chart for meal statistics.
    private var chartsView: some View {
        Chart {
            ForEach(mealStats) { stat in
                // Carbs Bar (bottom)
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.carbs)
                )
                .foregroundStyle(by: .value("Type", "Carbs"))
                .position(by: .value("Type", "Macros"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
                if state.useFPUconversion {
                    // Fat Bar (middle)
                    BarMark(
                        x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                        y: .value("Amount", stat.fat)
                    )
                    .foregroundStyle(by: .value("Type", "Fat"))
                    .position(by: .value("Type", "Macros"))
                    .opacity(
                        selectedDate.map { date in
                            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                        } ?? 1
                    )
                    // Protein Bar (top)
                    BarMark(
                        x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                        y: .value("Amount", stat.protein)
                    )
                    .foregroundStyle(by: .value("Type", "Protein"))
                    .position(by: .value("Type", "Macros"))
                    .opacity(
                        selectedDate.map { date in
                            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                        } ?? 1
                    )
                }
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate,
               let selectedMeal = getMealForDate(selectedDate)
            {
                RuleMark(
                    x: .value("Selected Date", selectedDate)
                )
                .foregroundStyle(Color.orange.opacity(0.5))
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
                        selectedDate: selectedDate,
                        selectedInterval: selectedInterval,
                        tint: .orange
                    ) {
                        Divider()

                        Grid(alignment: .leading) {
                            StatChartUtils.popoverRow(label: "Carbs:", value: selectedMeal.carbs, unit: "g")
                            if state.useFPUconversion {
                                StatChartUtils.popoverRow(label: "Fat:", value: selectedMeal.fat, unit: "g")
                                StatChartUtils.popoverRow(label: "Protein:", value: selectedMeal.protein, unit: "g")
                            }
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
        .chartForegroundStyleScale([
            "Carbs": Color.orange,
            "Fat": Color.purple,
            "Protein": Color.blue
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = state.useFPUconversion ? [
                (String(localized: "Carbs"), Color.orange),
                (String(localized: "Fat"), Color.purple),
                (String(localized: "Protein"), Color.blue)
            ] : [(String(localized: "Carbs"), Color.orange)]

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
        .accessibilityLabel(Text("Meal macronutrients bar chart"))
    }
}
