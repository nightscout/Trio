import Charts
import SwiftUI

struct MealStatsView: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let mealStats: [MealStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date() // gets updated in onAppear block
    @State private var selectedDate: Date?
    @State private var currentAverages: (carbs: Double, fat: Double, protein: Double) = (0, 0, 0)
    @State private var updateTimer = Stat.UpdateTimer()

    /// Returns the time interval length for the visible domain based on selected duration
    /// - Returns: TimeInterval representing the visible time range in seconds
    ///
    /// Time intervals:
    /// - Day: 24 hours (86400 seconds)
    /// - Week: 7 days (604800 seconds)
    /// - Month: 30 days (2592000 seconds)
    /// - Total: 90 days (7776000 seconds)
    private var visibleDomainLength: TimeInterval {
        switch selectedDuration {
        case .Day: return 24 * 3600 // One day in seconds
        case .Week: return 7 * 24 * 3600 // One week in seconds
        case .Month: return 30 * 24 * 3600 // One month in seconds (approximated)
        case .Total: return 90 * 24 * 3600 // Three months in seconds
        }
    }

    /// Calculates the visible date range based on scroll position and domain length
    /// - Returns: Tuple containing start and end dates of the visible range
    ///
    /// The start date is determined by the current scroll position, while the end date
    /// is calculated by adding the visible domain length to the start date
    private var visibleDateRange: (start: Date, end: Date) {
        let start = scrollPosition // Current scroll position marks the start
        let end = start.addingTimeInterval(visibleDomainLength)
        return (start, end)
    }

    /// Returns the appropriate date format style based on the selected time interval
    /// - Returns: A Date.FormatStyle configured for the current time interval
    ///
    /// Format styles:
    /// - Day: Shows hour only (e.g. "13")
    /// - Week: Shows abbreviated weekday (e.g. "Mon")
    /// - Month: Shows day of month (e.g. "15")
    /// - Total: Shows abbreviated month (e.g. "Jan")
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

    /// Returns DateComponents for aligning dates based on the selected duration
    /// - Returns: DateComponents configured for the appropriate alignment
    ///
    /// This property provides date components for aligning dates in the chart:
    /// - For Day view: Aligns to start of day (midnight)
    /// - For Week view: Aligns to Monday (weekday 2)
    /// - For Month/Total view: Aligns to first day of month
    private var alignmentComponents: DateComponents {
        switch selectedDuration {
        case .Day:
            return DateComponents(hour: 0) // Align to midnight
        case .Week:
            return DateComponents(weekday: 2) // Monday is weekday 2 in Calendar
        case .Month,
             .Total:
            return DateComponents(day: 1) // First day of month
        }
    }

    /// Returns meal statistics for a specific date
    /// - Parameter date: The date to find meal statistics for
    /// - Returns: MealStats object if found for the given date, nil otherwise
    ///
    /// This function searches through the meal statistics array to find the first entry
    /// that matches the provided date (comparing only the day component, not time).
    private func getMealForDate(_ date: Date) -> MealStats? {
        mealStats.first { stat in
            Calendar.current.isDate(stat.date, inSameDayAs: date)
        }
    }

    /// Updates the current averages for macronutrients based on the visible date range
    ///
    /// This function:
    /// - Gets the cached meal averages for the currently visible date range from the state
    /// - Updates the currentAverages property with the retrieved values (carbs, fat, protein)
    private func updateAverages() {
        // Get cached averages for visible time window
        currentAverages = state.getCachedMealAverages(for: visibleDateRange)
    }

    /// Formats the visible date range into a human-readable string
    /// - Returns: A formatted string representing the visible date range
    ///
    /// For Day view:
    /// - Uses relative terms like "Today", "Yesterday", "Tomorrow" when applicable
    /// - Shows time range in hours and minutes
    /// - Combines dates if start and end are on the same day
    ///
    /// For other views:
    /// - Uses standard date formatting
    private func formatVisibleDateRange() -> String {
        let start = visibleDateRange.start
        let end = visibleDateRange.end
        let calendar = Calendar.current
        let today = Date()

        let timeFormat = start.formatted(.dateTime.hour().minute())

        // Special handling for Day view with relative dates
        if selectedDuration == .Day {
            let startDateText: String
            let endDateText: String

            // Format start date
            if calendar.isDate(start, inSameDayAs: today) {
                startDateText = "Today"
            } else if calendar.isDate(start, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
                startDateText = "Yesterday"
            } else if calendar.isDate(start, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!) {
                startDateText = "Tomorrow"
            } else {
                startDateText = start.formatted(.dateTime.day().month())
            }

            // Format end date
            if calendar.isDate(end, inSameDayAs: today) {
                endDateText = "Today"
            } else if calendar.isDate(end, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
                endDateText = "Yesterday"
            } else if calendar.isDate(end, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!) {
                endDateText = "Tomorrow"
            } else {
                endDateText = end.formatted(.dateTime.day().month())
            }

            // If start and end are on the same day, show date only once
            if calendar.isDate(start, inSameDayAs: end) {
                return "\(startDateText), \(timeFormat) - \(end.formatted(.dateTime.hour().minute()))"
            }

            return "\(startDateText), \(timeFormat) - \(endDateText), \(end.formatted(.dateTime.hour().minute()))"
        }

        // Standard format for other views
        return "\(start.formatted()) - \(end.formatted())"
    }

    /// Returns the initial scroll position date based on the selected duration
    /// - Returns: A Date representing where the chart should initially scroll to
    ///
    /// This function calculates an appropriate starting scroll position by subtracting
    /// a time interval from the current date based on the selected duration:
    /// - For Day view: 1 day before now
    /// - For Week view: 7 days before now
    /// - For Month view: 1 month before now
    /// - For Total view: 3 months before now
    private func getInitialScrollPosition() -> Date {
        let calendar = Calendar.current
        let now = Date()

        // Calculate scroll position based on selected time interval
        switch selectedDuration {
        case .Day:
            return calendar.date(byAdding: .day, value: -1, to: now)!
        case .Week:
            return calendar.date(byAdding: .day, value: -7, to: now)!
        case .Month:
            return calendar.date(byAdding: .month, value: -1, to: now)!
        case .Total:
            return calendar.date(byAdding: .month, value: -3, to: now)!
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView
            chartsView
        }

        .onAppear {
            scrollPosition = getInitialScrollPosition()
            updateAverages()
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
            }
        }
        .onChange(of: selectedDuration) {
            Task {
                scrollPosition = getInitialScrollPosition()
                updateAverages()
            }
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

            Text(formatVisibleDateRange())
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Display formatted date header
            Text(date.formatted(.dateTime.month().day()))
                .font(.caption)
                .foregroundStyle(.secondary)

            // Grid layout for macronutrient values
            Grid(alignment: .leading) {
                // Carbohydrates row
                GridRow {
                    Text("Carbs:")
                    Text(meal.carbs.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("g")
                }
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
            .font(.caption)
        }
        .padding(8)
        .background(
            // Add background styling with shadow
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(radius: 2)
        )
    }
}
