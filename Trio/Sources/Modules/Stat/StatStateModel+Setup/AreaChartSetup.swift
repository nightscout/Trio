import Foundation

public struct HourlyStats: Equatable {
    let hour: Int
    let median: Double
    let percentile25: Double
    let percentile75: Double
    let percentile10: Double
    let percentile90: Double
}

extension Stat.StateModel {
    /// Empty hours return zeros so the chart always covers 00-23.
    static func makeHourlyStats(from readings: [GlucoseReading]) -> [HourlyStats] {
        let calendar = Calendar.current
        let groupedByHour = Dictionary(grouping: readings) { calendar.component(.hour, from: $0.date) }

        return (0 ... 23).map { hour in
            let values = groupedByHour[hour, default: []].map { Double($0.value) }.sorted()

            guard !values.isEmpty else {
                return HourlyStats(hour: hour, median: 0, percentile25: 0, percentile75: 0, percentile10: 0, percentile90: 0)
            }
            return HourlyStats(
                hour: hour,
                median: StatChartUtils.percentile(0.5, of: values),
                percentile25: StatChartUtils.percentile(0.25, of: values),
                percentile75: StatChartUtils.percentile(0.75, of: values),
                percentile10: StatChartUtils.percentile(0.10, of: values),
                percentile90: StatChartUtils.percentile(0.90, of: values)
            )
        }
    }
}
