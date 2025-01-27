import Charts
import SwiftUI

struct TDDChartView: View {
    let selectedDuration: Stat.StateModel.StatsTimeInterval
    let tddStats: [TDD]
    let calculateAverage: (Date, Date) -> Decimal

    @State private var scrollPosition = Date()
    @State private var currentAverageTDD: Decimal = 0
    @State private var selectedDate: Date?

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

    private var strideInterval: Calendar.Component {
        .day
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
            return DateComponents(hour: 0)
        case .Week:
            return DateComponents(weekday: 1)
        case .Month:
            return DateComponents(day: 1)
        case .Total:
            return DateComponents(day: 1, hour: 0)
        }
    }

    private var visibleDateRange: (start: Date, end: Date) {
        let halfDomain = visibleDomainLength / 2
        let start = scrollPosition.addingTimeInterval(-halfDomain)
        let end = scrollPosition.addingTimeInterval(halfDomain)
        return (start, end)
    }

    private func updateAverage() {
        let (start, end) = visibleDateRange
        currentAverageTDD = calculateAverage(start, end)
    }

    private func getTDDForDate(_ date: Date) -> TDD? {
        tddStats.first { tdd in
            guard let timestamp = tdd.timestamp else { return false }
            return Calendar.current.isDate(timestamp, inSameDayAs: date)
        }
    }

    var body: some View {
        chartCard
            .onChange(of: scrollPosition) {
                updateAverage()
            }
            .onAppear {
                updateAverage()
            }
    }

    // MARK: - Views

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total Daily Doses")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Average: \(currentAverageTDD.formatted(.number.precision(.fractionLength(1)))) U")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(
                        "\(visibleDateRange.start.formatted(.dateTime.month().day())) - \(visibleDateRange.end.formatted(.dateTime.month().day()))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Chart {
                ForEach(tddStats) { entry in
                    BarMark(
                        x: .value("Date", entry.timestamp ?? Date(), unit: strideInterval),
                        y: .value("Insulin", entry.totalDailyDose ?? 0)
                    )
                    .foregroundStyle(Color.insulin.gradient)
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
                AxisMarks(preset: .aligned, values: .stride(by: strideInterval)) { value in
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
