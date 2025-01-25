import Charts
import SwiftUI

struct GlucosePercentileChart: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let lowLimit: Decimal
    let isTodayOrLast24h: Bool
    let units: GlucoseUnits
    let hourlyStats: [HourlyStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ambulatory Glucose Profile (AGP)")
                .font(.headline)

            Chart {
//                if isTodayOrLast24h {
//                    // Single day line chart
//                    ForEach(glucose.sorted(by: { ($0.date ?? Date()) < ($1.date ?? Date()) }), id: \.id) { reading in
//                        LineMark(
//                            x: .value("Time", reading.date ?? Date()),
//                            y: .value("Glucose", Double(reading.glucose))
//                        )
//                        .lineStyle(StrokeStyle(lineWidth: 2))
//                        .foregroundStyle(.blue)
//                    }
//                } else {

                // TODO: ensure data is still correct
                // TODO: ensure area marks and line mark take color of respective range

                // Statistical view for longer periods
                // 10-90 percentile area
                ForEach(hourlyStats, id: \.hour) { stats in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("10th Percentile", stats.percentile10),
                        yEnd: .value("90th Percentile", stats.percentile90),
                        series: .value("10-90", "10-90")
                    )
                    .foregroundStyle(.blue.opacity(stats.median > 0 ? 0.2 : 0))
                }

                // 25-75 percentile area
                ForEach(hourlyStats, id: \.hour) { stats in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("25th Percentile", stats.percentile25),
                        yEnd: .value("75th Percentile", stats.percentile75),
                        series: .value("25-75", "25-75")
                    )
                    .foregroundStyle(.blue.opacity(stats.median > 0 ? 0.3 : 0))
                }

                // Median line
                ForEach(hourlyStats.filter { $0.median > 0 }, id: \.hour) { stats in
                    LineMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        y: .value("Median", stats.median),
                        series: .value("Median", "Median")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(.blue)
                }
//                }

                // High/Low limit lines
                RuleMark(y: .value("High Limit", Double(highLimit)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(.orange)

                RuleMark(y: .value("Low Limit", Double(lowLimit)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(.red)
            }
//            .chartYScale(domain: 40 ... 400)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartYAxisLabel(alignment: .leading) {
                Text("\(units.rawValue)")
                    .foregroundStyle(.primary)
                    .font(.caption)
                    .padding(.vertical, 3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                    AxisGridLine()
                }
            }
            .frame(height: 200)

            // Legend
//            if !isTodayOrLast24h {
            legend
//            }
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

private extension Calendar {
    func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }
}
