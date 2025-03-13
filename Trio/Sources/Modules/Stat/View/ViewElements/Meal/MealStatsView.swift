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
    /// The calculated macronutrient averages for the visible range.
    @State private var currentAverages: (carbs: Double, fat: Double, protein: Double) = (0, 0, 0)
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = Stat.UpdateTimer()
    /// The actual chart plot's width in pixel
    @State private var chartWidth: CGFloat = 0

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
                        + Text("\u{00A0}") + Text("g")
                }
                if state.useFPUconversion {
                    GridRow {
                        Text("Fat:")
                        Text(currentAverages.fat.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("g")
                    }
                    GridRow {
                        Text("Protein:")
                        Text(currentAverages.protein.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("g")
                    }
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Macro Nutrients (g)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chartsView
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { chartWidth = geo.size.width }
                                .onChange(of: geo.size.width) { _, newValue in chartWidth = newValue }
                        }
                    )
            }
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
            updateAverages()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
            }
        }
        .onChange(of: selectedInterval) {
            Task {
                scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
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
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    MealSelectionPopover(
                        selectedDate: selectedDate,
                        selectedMeal: selectedMeal,
                        selectedInterval: selectedInterval,
                        isFpuEnabled: state.useFPUconversion,
                        domain: visibleDateRange,
                        chartWidth: chartWidth
                    )
                }
            }

            // Dummy PointMark to force SwiftCharts to render a visible domain of 00:00-23:59
            // i.e. single day from midnight to midnight
            if selectedInterval == .day {
                let calendar = Calendar.current
                let midnight = calendar.startOfDay(for: Date())
                let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight)!

                PointMark(
                    x: .value("Time", nextMidnight),
                    y: .value("Dummy", 0)
                )
                .opacity(0) // ensures dummy ChartContent is hidden
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
            AxisMarks(preset: .aligned, values: .stride(by: selectedInterval == .day ? .hour : .day)) { value in
                if let date = value.as(Date.self) {
                    let day = Calendar.current.component(.day, from: date)
                    let hour = Calendar.current.component(.hour, from: date)

                    switch selectedInterval {
                    case .day:
                        if hour % 6 == 0 { // Show only every 6 hours
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .month:
                        if day % 3 == 0 { // Only show every 3rd day
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .total:
                        // Only show every other month
                        if day == 1 && Calendar.current.component(.month, from: date) % 2 == 1 {
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
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
                matching: selectedInterval == .day ?
                    DateComponents(minute: 0) :
                    DateComponents(hour: 0),
                majorAlignment: .matching(StatChartUtils.alignmentComponents(for: selectedInterval))
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval))
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
    let selectedDate: Date
    // The meal statistics to display
    let selectedMeal: MealStats
    // The selected duration in the time picker
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    // Setting controlling whether to display fat and protein
    let isFpuEnabled: Bool
    let domain: (start: Date, end: Date)
    let chartWidth: CGFloat

    @State private var popoverSize: CGSize = .zero

    @Environment(\.colorScheme) var colorScheme

    private var timeText: String {
        if selectedInterval == .day {
            let hour = Calendar.current.component(.hour, from: selectedDate)
            return selectedDate.formatted(.dateTime.month().day().weekday()) + "\n" + "\(hour):00-\(hour + 1):00"
        } else {
            return selectedDate.formatted(.dateTime.month().day().weekday())
        }
    }

    private func xOffset() -> CGFloat {
        let domainDuration = domain.end.timeIntervalSince(domain.start)
        guard domainDuration > 0, chartWidth > 0 else { return 0 }

        let popoverWidth = popoverSize.width

        // Convert dates to pixel'd x-condition
        let dateFraction = selectedDate.timeIntervalSince(domain.start) / domainDuration
        let x_selected = dateFraction * chartWidth

        // TODO: this is semi hacky, can this be improved?
        let x_left = x_selected - (popoverWidth / 2) // Left edge of popover
        let x_right = x_selected + (popoverWidth / 2) // Right edge of popover

        var offset: CGFloat = 0 // Default = no shift

        // Push popover to right if its left edge is (nearing) out-of-bounds
        if x_left < 0 {
            offset = abs(x_left) // push to right
        }

        // Push popover to left if its right edge is (nearing) out-of-bounds)
        if x_right > chartWidth {
            offset = -(x_right - chartWidth) // push to left
        }

        return offset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(.subheadline)
                .bold()
                .foregroundStyle(Color.secondary)

            Divider()

            // Grid layout for macronutrient values
            Grid(alignment: .leading) {
                // Carbohydrates row
                GridRow {
                    Text("Carbs:")
                    Text(selectedMeal.carbs.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("g").foregroundStyle(Color.secondary)
                }
                if isFpuEnabled {
                    // Fat row
                    GridRow {
                        Text("Fat:")
                        Text(selectedMeal.fat.formatted(.number.precision(.fractionLength(1))))
                            .gridColumnAlignment(.trailing)
                        Text("g").foregroundStyle(Color.secondary)
                    }
                    // Protein row
                    GridRow {
                        Text("Protein:")
                        Text(selectedMeal.protein.formatted(.number.precision(.fractionLength(1))))
                            .gridColumnAlignment(.trailing)
                        Text("g").foregroundStyle(Color.secondary)
                    }
                }
            }
            .font(.headline.bold())
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.orange, lineWidth: 2)
                )
        }
        .frame(minWidth: 100, maxWidth: .infinity) // Ensures proper width
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { popoverSize = geo.size }
                    .onChange(of: geo.size) { _, newValue in popoverSize = newValue }
            }
        )
        // Apply calculated xOffset to keep within bounds
        .offset(x: xOffset(), y: 0)
    }
}
