import Charts
import SwiftUI

struct MealStatsView: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let mealStats: [MealStats]
    let calculateAverages: @Sendable(Date, Date) async -> (carbs: Double, fat: Double, protein: Double)

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?
    @State private var currentAverages: (carbs: Double, fat: Double, protein: Double) = (0, 0, 0)
    @State private var updateTimer = Stat.UpdateTimer()

    private var visibleDomainLength: TimeInterval {
        switch selectedDuration {
        case .Day: return 24 * 3600 // 1 day
        case .Week: return 7 * 24 * 3600 // 1 week
        case .Month: return 30 * 24 * 3600 // 1 month
        case .Total: return 90 * 24 * 3600 // 3 months
        }
    }

    private var visibleDateRange: (start: Date, end: Date) {
        let halfDomain = visibleDomainLength / 2
        let start = scrollPosition.addingTimeInterval(-halfDomain)
        let end = scrollPosition.addingTimeInterval(halfDomain)
        return (start, end)
    }

    private var dateFormat: Date.FormatStyle {
        switch selectedDuration {
        case .Day:
            return .dateTime.weekday(.abbreviated)
        case .Week:
            return .dateTime.weekday(.abbreviated)
        case .Month:
            return .dateTime.day()
        case .Total:
            return .dateTime.month(.abbreviated)
        }
    }

    private var alignmentComponents: DateComponents {
        switch selectedDuration {
        case .Day:
            return DateComponents(hour: 0) // Align to start of day
        case .Week:
            return DateComponents(weekday: 2) // 2 = Monday in Calendar
        case .Month,
             .Total:
            return DateComponents(day: 1) // Align to first day of month
        }
    }

    private func getMealForDate(_ date: Date) -> MealStats? {
        mealStats.first { stat in
            Calendar.current.isDate(stat.date, inSameDayAs: date)
        }
    }

    private func updateAverages() {
        Task.detached(priority: .userInitiated) {
            let dateRange = await MainActor.run { visibleDateRange }
            let averages = await calculateAverages(dateRange.start, dateRange.end)

            await MainActor.run {
                currentAverages = averages
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView

            Chart {
                ForEach(mealStats) { stat in
                    // Carbs (Bottom)
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.carbs)
                    )
                    .foregroundStyle(by: .value("Type", "Carbs"))

                    // Fat (Middle)
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.fat)
                    )
                    .foregroundStyle(by: .value("Type", "Fat"))

                    // Protein (Top)
                    BarMark(
                        x: .value("Date", stat.date, unit: .day),
                        y: .value("Amount", stat.protein)
                    )
                    .foregroundStyle(by: .value("Type", "Protein"))
                }

                if let selectedDate,
                   let selectedMeal = getMealForDate(selectedDate)
                {
                    RuleMark(
                        x: .value("Selected Date", selectedDate)
                    )
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit, y: .disabled)
                    ) {
                        MealSelectionPopover(date: selectedDate, meal: selectedMeal)
                    }
                }
            }
            .chartForegroundStyleScale([
                "Carbs": Color.orange,
                "Fat": Color.blue,
                "Protein": Color.green
            ])
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let amount = value.as(Double.self) {
                        AxisValueLabel {
                            Text(amount.formatted(.number.precision(.fractionLength(1))) + " g")
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        let day = Calendar.current.component(.day, from: date)

                        switch selectedDuration {
                        case .Month:
                            if day % 5 == 0 { // Only show every 5th day
                                AxisValueLabel(format: dateFormat)
                                AxisGridLine()
                            }
                        case .Total:
                            // Only show January, April, July, October
                            if day == 1 && Calendar.current.component(.month, from: date) % 3 == 1 {
                                AxisValueLabel(format: dateFormat)
                                AxisGridLine()
                            }
                        default:
                            AxisValueLabel(format: dateFormat)
                            AxisGridLine()
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $scrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: alignmentComponents,
                    majorAlignment: .matching(alignmentComponents)
                )
            )
            .chartXVisibleDomain(length: visibleDomainLength)
            .frame(height: 200)
        }

        .onAppear {
            updateAverages()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
            }
        }
        .onChange(of: selectedDuration) {
            updateAverages()
            scrollPosition = Date()
        }
    }

    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Carbs:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.carbs.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("g")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Fat:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.fat.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("g")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Protein:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.protein.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("g")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(
                "\(visibleDateRange.start.formatted(.dateTime.month().day())) - \(visibleDateRange.end.formatted(.dateTime.month().day()))"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

private struct MealSelectionPopover: View {
    let date: Date
    let meal: MealStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.month().day()))
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading) {
                GridRow {
                    Text("Carbs:")
                    Text(meal.carbs.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("g")
                }
                GridRow {
                    Text("Fat:")
                    Text(meal.fat.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("g")
                }
                GridRow {
                    Text("Protein:")
                    Text(meal.protein.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("g")
                }
            }
            .font(.caption)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(radius: 2)
        )
    }
}
