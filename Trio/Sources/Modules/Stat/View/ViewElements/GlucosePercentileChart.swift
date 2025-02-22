import Charts
import SwiftUI

struct GlucosePercentileChart: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let hourlyStats: [HourlyStats]
    let isToday: Bool

    @State private var selection: Date? = nil

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ambulatory Glucose Profile (AGP)")
                .font(.headline)

            Chart {
                // TODO: ensure data is still correct
                // TODO: ensure area marks and line mark take color of respective range

                // Statistical view for longer periods
                ForEach(hourlyStats, id: \.hour) { stats in
                    // 10-90 percentile area
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("10th Percentile", stats.percentile10),
                        yEnd: .value("90th Percentile", stats.percentile90),
                        series: .value("10-90", "10-90")
                    )
                    .foregroundStyle(.blue.opacity(stats.median > 0 ? 0.2 : 0))

                    // 25-75 percentile area
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("25th Percentile", stats.percentile25),
                        yEnd: .value("75th Percentile", stats.percentile75),
                        series: .value("25-75", "25-75")
                    )
                    .foregroundStyle(.blue.opacity(stats.median > 0 ? 0.3 : 0))

                    // Median line
                    if stats.median > 0 {
                        LineMark(
                            x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                            y: .value("Median", stats.median),
                            series: .value("Median", "Median")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(.blue)
                    }
                }

                // High/Low limit lines
                RuleMark(y: .value("High Limit", Double(highLimit)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(.orange)

                RuleMark(y: .value("Low Limit", Double(lowLimit)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(.red)

                if let selectedStats, let selection {
                    RuleMark(x: .value("Selection", selection))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(
                            position: .top,
                            spacing: 0,
                            overflowResolution: .init(x: .fit, y: .disabled)
                        ) {
                            AGPSelectionPopover(
                                stats: selectedStats,
                                time: selection,
                                units: units
                            )
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let glucose = value.as(Double.self) {
                        AxisValueLabel {
                            Text(
                                units == .mmolL ? glucose.asMmolL.formatted(.number.precision(.fractionLength(0))) : glucose
                                    .formatted(.number.precision(.fractionLength(0)))
                            )
                            .font(.footnote)
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartYAxisLabel(alignment: .trailing) {
                Text("\(units.rawValue)")
                    .foregroundStyle(.primary)
                    .font(.footnote)
                    .padding(.vertical, 3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                        .font(.footnote)
                    AxisGridLine()
                }
            }
            .chartXSelection(value: $selection.animation(.easeInOut))
            .frame(height: 200)

            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 20) {
            VStack {
                // 10-90 Percentile
                HStack(spacing: 8) {
                    Rectangle()
                        .frame(width: 20, height: 8)
                        .foregroundStyle(.blue.opacity(0.2))
                    Text("10% - 90%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 25-75 Percentile
                HStack(spacing: 8) {
                    Rectangle()
                        .frame(width: 20, height: 8)
                        .foregroundStyle(.blue.opacity(0.3))
                    Text("25% - 75%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Median
            HStack(spacing: 8) {
                Rectangle()
                    .frame(width: 20, height: 2)
                    .foregroundStyle(.blue)
                Text("Median")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                // High Limit
                HStack(spacing: 8) {
                    Rectangle()
                        .frame(width: 20, height: 1)
                        .foregroundStyle(.orange)
                    Text("High Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Low Limit
                HStack(spacing: 8) {
                    Rectangle()
                        .frame(width: 20, height: 1)
                        .foregroundStyle(.red)
                    Text("Low Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct AGPSelectionPopover: View {
    let stats: HourlyStats
    let time: Date
    let units: GlucoseUnits

    private var timeText: String {
        if let hour = Calendar.current.dateComponents([.hour], from: time).hour {
            return "\(hour):00-\(hour + 1):00"
        } else {
            return time.formatted(.dateTime.hour().minute())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "clock")
                Text(timeText)
                    .fontWeight(.bold)
            }
            .font(.subheadline)

            Grid(alignment: .leading, horizontalSpacing: 8) {
                GridRow {
                    Text("90%:")
                    Text(units == .mmolL ? stats.percentile90.asMmolL.formatted(.number) : stats.percentile90.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("75%:")
                    Text(units == .mmolL ? stats.percentile75.asMmolL.formatted(.number) : stats.percentile75.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Median:")
                    Text(units == .mmolL ? stats.median.asMmolL.formatted(.number) : stats.median.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("25%:")
                    Text(units == .mmolL ? stats.percentile25.asMmolL.formatted(.number) : stats.percentile25.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("10%:")
                    Text(units == .mmolL ? stats.percentile10.asMmolL.formatted(.number) : stats.percentile10.formatted(.number))
                    Text(units.rawValue)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.headline.bold())
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue)
        }
    }
}

private extension Calendar {
    func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }
}
