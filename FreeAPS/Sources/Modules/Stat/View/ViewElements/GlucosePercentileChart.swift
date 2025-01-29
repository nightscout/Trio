import Charts
import SwiftUI

struct GlucosePercentileChart: View {
    @Binding var selectedDuration: Stat.StateModel.StatsTimeInterval
    let state: Stat.StateModel
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let hourlyStats: [HourlyStats]

    @State private var scrollPosition = Date()
    @State private var selection: Date?
    @State private var isScrolling = false
    @State private var updateTimer = Stat.UpdateTimer()

    private func getDataRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current

        switch selectedDuration {
        case .Day:
            return (
                calendar.startOfDay(for: scrollPosition),
                calendar.startOfDay(for: scrollPosition).addingTimeInterval(24 * 3600)
            )
        case .Week:
            let weekStart = calendar
                .date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: scrollPosition))!
            return (weekStart, weekStart.addingTimeInterval(7 * 24 * 3600))
        case .Month:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: scrollPosition))!
            return (monthStart, calendar.date(byAdding: .month, value: 1, to: monthStart)!)
        case .Total:
            return (
                calendar.date(byAdding: .month, value: -3, to: scrollPosition)!,
                scrollPosition
            )
        }
    }

    private var visibleDateRange: (start: Date, end: Date) {
        let calendar = Calendar.current

        // Die X-Achse zeigt immer einen 24h-Tag
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
                VStack(alignment: .leading) {
                    Text("Ambulatory Glucose Profile")
                        .font(.headline)
                    Text("(AGP)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formatVisibleDateRange())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart {
                // TODO: ensure data is still correct
                // TODO: ensure area marks and line mark take color of respective range

                // Statistical view for longer periods
                // 10-90 percentile area
                ForEach(hourlyStats, id: \.hour) { stats in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour), unit: .hour),
                        yStart: .value("10th Percentile", stats.percentile10),
                        yEnd: .value("90th Percentile", stats.percentile90),
                        series: .value("10-90", "10-90")
                    )
                    .foregroundStyle(.blue.opacity(stats.median > 0 ? 0.2 : 0))
                }

                // 25-75 percentile area
                ForEach(hourlyStats, id: \.hour) { stats in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour), unit: .hour),
                        yStart: .value("25th Percentile", stats.percentile25),
                        yEnd: .value("75th Percentile", stats.percentile75),
                        series: .value("25-75", "25-75")
                    )
                    .foregroundStyle(.blue.opacity(stats.median > 0 ? 0.3 : 0))
                }

                // Median line
                ForEach(hourlyStats.filter { $0.median > 0 }, id: \.hour) { stats in
                    LineMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour), unit: .hour),
                        y: .value("Median", stats.median),
                        series: .value("Median", "Median")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(.blue)
                }

                // Target range
                RuleMark(
                    y: .value("High Limit", highLimit)
                )
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [10, 5]))
                .foregroundStyle(.orange.gradient)

                // TODO: - Get target
                RuleMark(
                    y: .value("Target", 100)
                )
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(.green.gradient)

                RuleMark(
                    y: .value("Low Limit", lowLimit)
                )
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [10, 5]))
                .foregroundStyle(.red.gradient)

                if let selection = selection,
                   let stats = selectedStats
                {
                    RuleMark(
                        x: .value("Selected Time", selection)
                    )
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit, y: .disabled)
                    ) {
                        AGPSelectionPopover(
                            stats: stats,
                            time: selection,
                            units: units
                        )
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let glucose = value.as(Double.self) {
                        let glucoseValue = units == .mmolL ? Decimal(glucose).asMmolL : Decimal(glucose)
                        AxisValueLabel {
                            Text(glucoseValue.formatted(.number.precision(.fractionLength(units == .mmolL ? 1 : 0))))
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), centered: true, anchor: .top)
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
        // Update chart when scrolling
        .onChange(of: scrollPosition) {
            state.glucoseScrollPosition = scrollPosition
            state.updateDisplayedStats(for: .percentile)
        }
        // Reset scroll position when duration changes
        .onChange(of: selectedDuration) {
            scrollPosition = Date()
            state.glucoseScrollPosition = scrollPosition
        }
    }

    private var selectedStats: HourlyStats? {
        guard let selection = selection else { return nil }

        // Don't show stats for future times if viewing today
        if isToday && selection > Date() {
            return nil
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selection)
        return hourlyStats.first { Int($0.hour) == hour }
    }

    private var isToday: Bool {
        let calendar = Calendar.current
        let now = Date()
        return calendar.isDate(now, inSameDayAs: calendar.startOfDay(for: now))
    }
}

struct AGPSelectionPopover: View {
    let stats: HourlyStats
    let time: Date
    let units: GlucoseUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "clock")
                Text(time.formatted(.dateTime.hour().minute(.twoDigits)))
                    .font(.body).bold()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8) {
                GridRow {
                    Text("90%:")
                    Text(stats.percentile90.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("75%:")
                    Text(stats.percentile75.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Median:")
                    Text(stats.median.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("25%:")
                    Text(stats.percentile25.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("10%:")
                    Text(stats.percentile10.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(radius: 2)
        }
    }
}

private extension Calendar {
    func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }
}
