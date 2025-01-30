import Charts
import SwiftUI

struct BolusStatsView: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let bolusStats: [BolusStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date() // gets updated in onAppear block
    @State private var selectedDate: Date?
    @State private var currentAverages: (manual: Double, smb: Double, external: Double) = (0, 0, 0)
    @State private var updateTimer = Stat.UpdateTimer()

    /// Returns the time interval length for the visible domain based on selected duration
    private var visibleDomainLength: TimeInterval {
        switch selectedDuration {
        case .Day: return 24 * 3600 // One day in seconds
        case .Week: return 7 * 24 * 3600 // One week in seconds
        case .Month: return 30 * 24 * 3600 // One month in seconds
        case .Total: return 90 * 24 * 3600 // Three months in seconds
        }
    }

    /// Calculates the visible date range based on scroll position and domain length
    private var visibleDateRange: (start: Date, end: Date) {
        let start = scrollPosition // Current scroll position marks the start
        let end = start.addingTimeInterval(visibleDomainLength)
        return (start, end)
    }

    /// Returns the appropriate date format style based on the selected time interval
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
    private var alignmentComponents: DateComponents {
        switch selectedDuration {
        case .Day:
            return DateComponents(hour: 0) // Align to midnight
        case .Week:
            return DateComponents(weekday: 2) // Monday is weekday 2
        case .Month,
             .Total:
            return DateComponents(day: 1) // First day of month
        }
    }

    /// Returns bolus statistics for a specific date
    private func getBolusForDate(_ date: Date) -> BolusStats? {
        let calendar = Calendar.current

        return bolusStats.first { stat in
            switch selectedDuration {
            case .Day:
                return calendar.isDate(stat.date, equalTo: date, toGranularity: .hour)
            default:
                return calendar.isDate(stat.date, inSameDayAs: date)
            }
        }
    }

    /// Updates the current averages for bolus insulin based on the visible date range
    private func updateAverages() {
        currentAverages = state.getCachedBolusAverages(for: visibleDateRange)
    }

    /// Formats the visible date range into a human-readable string
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

    private func isSameTimeUnit(_ date1: Date, _ date2: Date) -> Bool {
        switch selectedDuration {
        case .Day:
            return Calendar.current.isDate(date1, equalTo: date2, toGranularity: .hour)
        default:
            return Calendar.current.isDate(date1, inSameDayAs: date2)
        }
    }

    /// Returns the initial scroll position date based on the selected duration
    private func getInitialScrollPosition() -> Date {
        let calendar = Calendar.current
        let now = Date()

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
                    Text("Manual:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.manual.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("SMB:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.smb.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("External:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverages.external.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
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
            ForEach(bolusStats) { stat in
                // Total Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.manualBolus)
                )
                .foregroundStyle(by: .value("Type", "Manual"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        isSameTimeUnit(stat.date, date) ? 1 : 0.3
                    } ?? 1
                )

                // Carb Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.smb)
                )
                .foregroundStyle(by: .value("Type", "SMB"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        isSameTimeUnit(stat.date, date) ? 1 : 0.3
                    } ?? 1
                )
                // Correction Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.external)
                )
                .foregroundStyle(by: .value("Type", "External"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        isSameTimeUnit(stat.date, date) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate, let selectedBolus = getBolusForDate(selectedDate)
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
                    BolusSelectionPopover(date: selectedDate, bolus: selectedBolus, selectedDuration: selectedDuration)
                }
            }
        }
        .chartForegroundStyleScale([
            "SMB": Color.blue,
            "Manual": Color.teal,
            "External": Color.purple
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(amount.formatted(.number.precision(.fractionLength(0))) + " U")
                            .font(.subheadline)
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
                            AxisValueLabel(format: dateFormat, centered: true)
                                .font(.subheadline)
                            AxisGridLine()
                        }
                    case .Month:
                        if day % 5 == 0 { // Only show every 5th day
                            AxisValueLabel(format: dateFormat, centered: true)
                                .font(.subheadline)
                            AxisGridLine()
                        }
                    case .Total:
                        // Only show January, April, July, October
                        if day == 1 && Calendar.current.component(.month, from: date) % 3 == 1 {
                            AxisValueLabel(format: dateFormat, centered: true)
                                .font(.subheadline)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: dateFormat, centered: true)
                            .font(.subheadline)
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
                    DateComponents(minute: 0) : // Align to next hour for Day view
                    DateComponents(hour: 0), // Align to start of day for other views
                majorAlignment: .matching(
                    alignmentComponents
                )
            )
        )
        .chartXVisibleDomain(length: visibleDomainLength)
        .frame(height: 250)
    }
}

private struct BolusSelectionPopover: View {
    let date: Date
    let bolus: BolusStats
    let selectedDuration: Stat.StateModel.StatsTimeInterval
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedDuration == .Day ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.month().day()))
                .font(.subheadline)
                .fontWeight(.bold)

            Grid(alignment: .leading) {
                GridRow {
                    Text("Manual:")
                    Text(bolus.manualBolus.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("U")
                }
                GridRow {
                    Text("SMB:")
                    Text(bolus.smb.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("U")
                }
                GridRow {
                    Text("External:")
                    Text(bolus.external.formatted(.number.precision(.fractionLength(1))))
                        .gridColumnAlignment(.trailing)
                    Text("U")
                }
            }
            .font(.headline.bold())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.gradient)
        )
    }
}
