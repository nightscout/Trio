import Charts
import SwiftUI

/// A view that displays a bar chart for meal statistics.
///
/// This view presents macronutrient intake (carbohydrates, fats, and proteins) over time,
/// allowing users to adjust the time interval and scroll through historical data.
struct MealStatsView: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    /// The list of meal statistics data.
    let mealStats: [MealStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The calculated macronutrient averages for the visible range.
    @State private var currentAverages: (carbs: Double, fat: Double, protein: Double) = (0, 0, 0)
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = Stat.UpdateTimer()

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedDuration)
    }

    /// Retrieves the meal statistic for a given date.
    /// - Parameter date: The date for which to retrieve meal data.
    /// - Returns: The `MealStats` object if available, otherwise `nil`.
    private func getMealForDate(_ date: Date) -> MealStats? {
        mealStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedDuration)
        }
    }

    /// Updates the macronutrient averages based on the visible date range.
    private func updateAverages() {
        currentAverages = state.getCachedMealAverages(for: visibleDateRange)
    }

    /// A view displaying the statistics summary including macronutrient averages.
    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Carbs:")
                    Text(currentAverages.carbs.formatted(.number.precision(.fractionLength(1))))
                    Text("g")
                }
                if state.useFPUconversion {
                    GridRow {
                        Text("Fat:")
                        Text(currentAverages.fat.formatted(.number.precision(.fractionLength(1))))
                        Text("g")
                    }
                    GridRow {
                        Text("Protein:")
                        Text(currentAverages.protein.formatted(.number.precision(.fractionLength(1))))
                        Text("g")
                    }
                }
            }
            .font(.headline)

            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedDuration)
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
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedDuration)
            updateAverages()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
            }
        }
        .onChange(of: selectedDuration) {
            Task {
                scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedDuration)
                updateAverages()
            }
        }
    }

    /// A view displaying the bar chart for meal statistics.
    private var chartsView: some View {
        Chart {
            ForEach(mealStats) { stat in
                // Carbs Bar (bottom)
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.carbs)
                )
                .foregroundStyle(by: .value("Type", "Carbs"))
                .position(by: .value("Type", "Macros"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedDuration) ? 1 : 0.3
                    } ?? 1
                )
                if state.useFPUconversion {
                    // Fat Bar (middle)
                    BarMark(
                        x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                        y: .value("Amount", stat.fat)
                    )
                    .foregroundStyle(by: .value("Type", "Fat"))
                    .position(by: .value("Type", "Macros"))
                    .opacity(
                        selectedDate.map { date in
                            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedDuration) ? 1 : 0.3
                        } ?? 1
                    )
                    // Protein Bar (top)
                    BarMark(
                        x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                        y: .value("Amount", stat.protein)
                    )
                    .foregroundStyle(by: .value("Type", "Protein"))
                    .position(by: .value("Type", "Macros"))
                    .opacity(
                        selectedDate.map { date in
                            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedDuration) ? 1 : 0.3
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
                .foregroundStyle(.secondary.opacity(0.5))
                .annotation(
                    position: .top,
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    MealSelectionPopover(
                        date: selectedDate,
                        meal: selectedMeal,
                        selectedDuration: selectedDuration,
                        isFpuEnabled: state.useFPUconversion
                    )
                }
            }
        }
        .chartForegroundStyleScale([
            "Carbs": Color.orange,
            "Protein": Color.blue,
            "Fat": Color.purple
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = state.useFPUconversion ? [
                (String(localized: "Carbs"), Color.orange),
                (String(localized: "Protein"), Color.blue),
                (String(localized: "Fat"), Color.purple)
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
            AxisMarks(preset: .aligned, values: .stride(by: selectedDuration == .Day ? .hour : .day)) { value in
                if let date = value.as(Date.self) {
                    let day = Calendar.current.component(.day, from: date)
                    let hour = Calendar.current.component(.hour, from: date)

                    switch selectedDuration {
                    case .Day:
                        if hour % 6 == 0 { // Show only every 6 hours
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .Month:
                        if day % 3 == 0 { // Only show every 3rd day
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .Total:
                        // Only show every other month
                        if day == 1 && Calendar.current.component(.month, from: date) % 2 == 1 {
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedDuration), centered: true)
                            .font(.footnote)
                        AxisGridLine()
                    }
                }
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: selectedDuration == .Day ?
                    DateComponents(minute: 0) :
                    DateComponents(hour: 0),
                majorAlignment: .matching(StatChartUtils.alignmentComponents(for: selectedDuration))
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedDuration))
        .frame(height: 250)
    }
}

/// A view that displays detailed meal information in a popover
///
/// This view shows a formatted display of meal macronutrients including:
/// - Date of the meal
/// - Carbohydrates in grams
/// - Fat in grams
/// - Protein in grams
private struct MealSelectionPopover: View {
    // The date when the meal was logged
    let date: Date
    // The meal statistics to display
    let meal: MealStats
    // The selected duration in the time picker
    let selectedDuration: Stat.StateModel.StatsTimeInterval
    // Setting controlling whether to display fat and protein
    let isFpuEnabled: Bool

    private var timeText: String {
        if selectedDuration == .Day {
            let hour = Calendar.current.component(.hour, from: date)
            return "\(hour):00-\(hour + 1):00"
        } else {
            return date.formatted(.dateTime.month().day())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Display formatted date header
            Text(timeText)
                .font(.footnote)
                .fontWeight(.bold)

            // Grid layout for macronutrient values
            Grid(alignment: .leading) {
                // Carbohydrates row
                GridRow {
                    Text("Carbs:")
                    Text(meal.carbs.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("g")
                }
                if isFpuEnabled {
                    // Fat row
                    GridRow {
                        Text("Fat:")
                        Text(meal.fat.formatted(.number.precision(.fractionLength(1))))
                            .gridColumnAlignment(.trailing)
                        Text("g")
                    }
                    // Protein row
                    GridRow {
                        Text("Protein:")
                        Text(meal.protein.formatted(.number.precision(.fractionLength(1))))
                            .gridColumnAlignment(.trailing)
                        Text("g")
                    }
                }
            }
            .font(.headline.bold())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange)
        )
    }
}
