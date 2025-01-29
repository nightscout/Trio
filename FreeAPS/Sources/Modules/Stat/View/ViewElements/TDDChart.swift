import Charts
import SwiftUI

struct TDDChartView: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let tddStats: [TDD]
    let calculateAverage: @Sendable(Date, Date) async -> Decimal
    let calculateMedian: @Sendable(Date, Date) async -> Decimal

    @State private var scrollPosition = Date()
    @State private var currentAverageTDD: Decimal = 0
    @State private var currentMedianTDD: Decimal = 0
    @State private var selectedDate: Date?
    @State private var isScrolling = false

    @State private var updateTimer = Stat.UpdateTimer()

    private var visibleDomainLength: TimeInterval {
        switch selectedDuration {
        case .Day: return 3 * 24 * 3600 // 3 days
        case .Week: return 7 * 24 * 3600 // 1 week
        case .Month: return 30 * 24 * 3600 // 1 month
        case .Total: return 90 * 24 * 3600 // 3 months
        }
    }

    private var scrollTargetDuration: TimeInterval {
        switch selectedDuration {
        case .Day: return 3 * 24 * 3600 // Scroll by 3 days
        case .Week: return 7 * 24 * 3600 // Scroll by 1 week
        case .Month: return 30 * 24 * 3600 // Scroll by 1 month
        case .Total: return 90 * 24 * 3600 // Scroll by 3 months
        }
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

    private var visibleDateRange: (start: Date, end: Date) {
        let halfDomain = visibleDomainLength / 2
        let start = scrollPosition.addingTimeInterval(-halfDomain)
        let end = scrollPosition.addingTimeInterval(halfDomain)
        return (start, end)
    }

    private func updateStats() {
        Task.detached(priority: .userInitiated) {
            let dateRange = await MainActor.run { visibleDateRange }
            let avgTDD = await calculateAverage(dateRange.start, dateRange.end)
            let medTDD = await calculateMedian(dateRange.start, dateRange.end)

            await MainActor.run {
                currentAverageTDD = avgTDD
                currentMedianTDD = medTDD
            }
        }
    }

    private func getTDDForDate(_ date: Date) -> TDD? {
        tddStats.first { tdd in
            guard let timestamp = tdd.timestamp else { return false }
            return Calendar.current.isDate(timestamp, inSameDayAs: date)
        }
    }

    var body: some View {
        chartCard
            .onAppear {
                updateStats()
            }
            .onChange(of: scrollPosition) {
                isScrolling = true
                updateTimer.scheduleUpdate {
                    updateStats()
                    isScrolling = false
                }
            }
            .onChange(of: selectedDuration) {
                updateStats()
                scrollPosition = Date()
            }
    }

    // MARK: - Views

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView

            Chart {
                ForEach(tddStats) { entry in
                    BarMark(
                        x: .value("Date", entry.timestamp ?? Date(), unit: selectedDuration == .Day ? .hour : .day),
                        y: .value("TDD", entry.totalDailyDose ?? 0)
                    )
                    .foregroundStyle(Color.insulin)
                }

                if let selectedDate,
                   let selectedTDD = getTDDForDate(selectedDate)
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
                        TDDSelectionPopover(date: selectedDate, tdd: selectedTDD)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                    AxisGridLine()
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
                                AxisGridLine()
                            }
                        case .Month:
                            if day % 5 == 0 { // Only show every 5th day
                                AxisValueLabel(format: dateFormat, centered: true)
                                AxisGridLine()
                            }
                        case .Total:
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
                    majorAlignment: .matching(alignmentComponents)
                )
            )
            .chartXVisibleDomain(length: visibleDomainLength)
            .frame(height: 200)
        }
    }

    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Average:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentAverageTDD.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Median:")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(currentMedianTDD.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("U")
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

    private struct TDDSelectionPopover: View {
        let date: Date
        let tdd: TDD

        var body: some View {
            VStack(alignment: .center, spacing: 4) {
                Text(date.formatted(.dateTime.month().day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(tdd.totalDailyDose?.formatted(.number.precision(.fractionLength(1))) ?? "0") U")
                    .font(.callout.bold())
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 2)
            )
        }
    }
}
