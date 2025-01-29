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
    @State private var isScrolling = false

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
            return .dateTime.hour()
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

    private func formatVisibleDateRange(showTimeRange: Bool = false) -> String {
        let start = visibleDateRange.start
        let end = visibleDateRange.end
        let calendar = Calendar.current

        switch selectedDuration {
        case .Day:
            let today = Date()
            let isToday = calendar.isDate(start, inSameDayAs: today)
            let isYesterday = calendar.isDate(start, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!)

            if isToday || isYesterday, !showTimeRange {
                return isToday ? "Today" : "Yesterday"
            }

            let timeRange =
                "\(start.formatted(.dateTime.hour(.twoDigits(amPM: .wide)))) - \(end.formatted(.dateTime.hour(.twoDigits(amPM: .wide))))"

            if isToday {
                return "Today, \(timeRange)"
            } else if isYesterday {
                return "Yesterday, \(timeRange)"
            } else {
                return "\(start.formatted(.dateTime.month().day())), \(timeRange)"
            }

        default:
            return "\(start.formatted(.dateTime.month().day())) - \(end.formatted(.dateTime.month().day()))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView

            chartsView
        }

        .onAppear {
            updateAverages()
        }
        .onChange(of: scrollPosition) {
            isScrolling = true
            updateTimer.scheduleUpdate {
                updateAverages()
                isScrolling = false
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

            Text(formatVisibleDateRange(showTimeRange: isScrolling))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var chartsView: some View {
        Chart {
            ForEach(mealStats) { stat in
                // Carbs Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.carbs)
                )
                .foregroundStyle(by: .value("Type", "Carbs"))
                .position(by: .value("Type", "Carbs"))

                // Fat Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.fat)
                )
                .foregroundStyle(by: .value("Type", "Fat"))
                .position(by: .value("Type", "Fat"))

                // Protein Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.protein)
                )
                .foregroundStyle(by: .value("Type", "Protein"))
                .position(by: .value("Type", "Protein"))
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
                        Text(amount.formatted(.number.precision(.fractionLength(0))) + " g")
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
                        if hour % 6 == 0 { // Show only every 6 hours (0, 6, 12, 18)
                            AxisValueLabel(format: dateFormat, centered: true)
                            AxisGridLine()
                        }
                    case .Month:
                        if day % 5 == 0 { // Only show every 5th day
                            AxisValueLabel(format: dateFormat, centered: true)
                            AxisGridLine()
                        }
                    case .Total:
                        // Only show January, April, July, October
                        if day == 1 && Calendar.current.component(.month, from: date) % 3 == 1 {
                            AxisValueLabel(format: dateFormat, centered: true)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: dateFormat, centered: true)
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
                matching: selectedDuration == .Day ?
                    DateComponents(minute: 0) : // Align to next hour for Day view
                    DateComponents(hour: 0), // Align to start of day for other views
                majorAlignment: .matching(
                    alignmentComponents
                )
            )
        )
        .chartXVisibleDomain(length: visibleDomainLength)
        .frame(height: 200)
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
