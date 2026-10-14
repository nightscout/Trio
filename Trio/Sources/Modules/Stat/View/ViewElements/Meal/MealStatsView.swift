import Charts
import SwiftUI

struct MealStatsView: View {
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    let mealStats: [MealStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?

    private var headlineValues: (carbs: Double, fat: Double, protein: Double) {
        selectedInterval == .day
            ? state.calculateMealTotals(for: visibleDateRange)
            : state.calculateMealAverages(for: visibleDateRange)
    }

    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    private func getMealForDate(_ date: Date) -> MealStats? {
        mealStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

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

    private var chartsView: some View {
        Chart {
            ForEach(mealStats) { stat in
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
                        title: StatChartUtils.selectionTitle(for: selectedDate, showHourRange: selectedInterval == .day),
                        tint: .orange
                    ) {
                        Grid(alignment: .leading) {
                            StatChartUtils.popoverRow(
                                label: "Carbs:",
                                formattedValue: StatChartUtils.format(selectedMeal.carbs),
                                unit: "g"
                            )
                            if state.useFPUconversion {
                                StatChartUtils.popoverRow(
                                    label: "Fat:",
                                    formattedValue: StatChartUtils.format(selectedMeal.fat),
                                    unit: "g"
                                )
                                StatChartUtils.popoverRow(
                                    label: "Protein:",
                                    formattedValue: StatChartUtils.format(selectedMeal.protein),
                                    unit: "g"
                                )
                            }
                        }
                    }
                }
            }

            if selectedInterval == .day {
                StatChartUtils.fullDayDomainAnchor()
            }
        }
        .chartForegroundStyleScale(state.useFPUconversion ? [
            "Carbs": Color.orange,
            "Fat": Color.purple,
            "Protein": Color.blue
        ] : ["Carbs": Color.orange])
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
        .accessibilityLabel(Text("Meal macronutrients bar chart"))
    }
}
