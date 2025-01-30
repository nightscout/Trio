import Charts
import SwiftUI

struct TDDChartView: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let tddStats: [TDDStats]
    let state: Stat.StateModel

    @State private var scrollPosition = Date()
    @State private var selectedDate: Date?
    @State private var currentAverage: Double = 0
    @State private var updateTimer = Stat.UpdateTimer()

    private var visibleDomainLength: TimeInterval {
        switch selectedDuration {
        case .Day: return 24 * 3600
        case .Week: return 7 * 24 * 3600
        case .Month: return 30 * 24 * 3600
        case .Total: return 90 * 24 * 3600
        }
    }

    private var visibleDateRange: (start: Date, end: Date) {
        let start = scrollPosition
        let end = start.addingTimeInterval(visibleDomainLength)
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
            return DateComponents(hour: 0)
        case .Week:
            return DateComponents(weekday: 2)
        case .Month,
             .Total:
            return DateComponents(day: 1)
        }
    }

    private func getTDDForDate(_ date: Date) -> TDDStats? {
        let calendar = Calendar.current

        return tddStats.first { stat in
            switch selectedDuration {
            case .Day:
                return calendar.isDate(stat.date, equalTo: date, toGranularity: .hour)
            default:
                return calendar.isDate(stat.date, inSameDayAs: date)
            }
        }
    }

    private func updateAverages() {
        currentAverage = state.getCachedTDDAverages(for: visibleDateRange)
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

    private func isSameTimeUnit(_ date1: Date, _ date2: Date) -> Bool {
        switch selectedDuration {
        case .Day:
            return Calendar.current.isDate(date1, equalTo: date2, toGranularity: .hour)
        default:
            return Calendar.current.isDate(date1, inSameDayAs: date2)
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
            Text("Average:")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(currentAverage.formatted(.number.precision(.fractionLength(1))))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("U")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(formatVisibleDateRange())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedDuration == .Day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(Color.insulin)
                .opacity(
                    selectedDate.map { date in
                        isSameTimeUnit(stat.date, date) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate,
               let selectedTDD = getTDDForDate(selectedDate)
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
                    TDDSelectionPopover(date: selectedDate, tdd: selectedTDD, selectedDuration: selectedDuration)
                }
            }
        }
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
                        if hour % 6 == 0 {
                            AxisValueLabel(format: dateFormat, centered: true)
                                .font(.subheadline)
                            AxisGridLine()
                        }
                    case .Month:
                        if day % 5 == 0 {
                            AxisValueLabel(format: dateFormat, centered: true)
                                .font(.subheadline)
                            AxisGridLine()
                        }
                    case .Total:
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
                    DateComponents(minute: 0) :
                    DateComponents(hour: 0),
                majorAlignment: .matching(alignmentComponents)
            )
        )
        .chartXVisibleDomain(length: visibleDomainLength)
        .frame(height: 250)
    }
}

private struct TDDSelectionPopover: View {
    let date: Date
    let tdd: TDDStats
    let selectedDuration: Stat.StateModel.StatsTimeInterval
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedDuration == .Day ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.month().day()))
                .font(.subheadline)
                .fontWeight(.bold)

            Text(tdd.amount.formatted(.number.precision(.fractionLength(1))) + " U")
                .font(.title3.bold())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.insulin.gradient)
        }
    }
}
