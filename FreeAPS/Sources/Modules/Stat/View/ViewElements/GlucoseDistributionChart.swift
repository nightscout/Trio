import Charts
import SwiftUI

struct GlucoseDistributionChart: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let state: Stat.StateModel
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let glucoseRangeStats: [Stat.GlucoseRangeStats]

    @State private var scrollPosition = Date()
    @State private var selection: Date?

    private var visibleDateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        return (
            calendar.startOfDay(for: scrollPosition),
            calendar.startOfDay(for: scrollPosition).addingTimeInterval(24 * 3600)
        )
    }

    private func formatVisibleDateRange() -> String {
        let calendar = Calendar.current
        let today = Date()

        switch selectedDuration {
        case .Day:
            let isToday = calendar.isDate(scrollPosition, inSameDayAs: today)
            let isYesterday = calendar.isDate(
                scrollPosition,
                inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!
            )

            return if isToday {
                "Today"
            } else if isYesterday {
                "Yesterday"
            } else {
                scrollPosition.formatted(date: .numeric, time: .omitted)
            }

        case .Week:
            let weekStart = calendar
                .date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: scrollPosition))!
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            return "\(weekStart.formatted(date: .numeric, time: .omitted)) - \(weekEnd.formatted(date: .numeric, time: .omitted))"

        case .Month:
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: scrollPosition)
            )!
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthEnd)!
            return "\(monthStart.formatted(date: .numeric, time: .omitted)) - \(lastDayOfMonth.formatted(date: .numeric, time: .omitted))"

        case .Total:
            let endDate = scrollPosition
            let startDate = calendar.date(byAdding: .month, value: -3, to: endDate)!
            return "\(startDate.formatted(date: .numeric, time: .omitted)) - \(endDate.formatted(date: .numeric, time: .omitted))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Glucose Distribution")
                    .font(.headline)

                Spacer()

                Text(formatVisibleDateRange())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart(glucoseRangeStats) { range in
                ForEach(range.values, id: \.hour) { value in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(value.hour)),
                        y: .value("Count", value.count),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Range", range.name))
                }
            }
            .chartForegroundStyleScale([
                "<54": .purple.opacity(0.7),
                "54-70": .red.opacity(0.7),
                "70-140": .green,
                "140-180": .green.opacity(0.7),
                "180-200": .yellow.opacity(0.7),
                "200-220": .orange.opacity(0.7),
                ">220": .orange.opacity(0.8)
            ])
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                    AxisGridLine()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $scrollPosition)
            .chartXSelection(value: $selection)
            .chartXVisibleDomain(length: 24 * 3600)
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: DateComponents(minute: 0),
                    majorAlignment: .matching(DateComponents(hour: 0))
                )
            )
            .frame(height: 200)
        }
        .onChange(of: scrollPosition) {
            state.glucoseScrollPosition = scrollPosition
            state.updateDisplayedStats(for: .distribution)
        }
    }
}
