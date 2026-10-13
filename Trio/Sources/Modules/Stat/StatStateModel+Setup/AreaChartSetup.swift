import Foundation

/// Represents statistical values for glucose readings grouped by hour of the day.
///
/// This struct contains various percentile calculations that help visualize
/// glucose distribution patterns throughout the day:
///
/// - The median (50th percentile) shows the central tendency
/// - The 25th and 75th percentiles form the interquartile range (IQR)
/// - The 10th and 90th percentiles show the wider range of values
///
/// Example usage in visualization:
/// ```
/// let stats = HourlyStats(
///     hour: 14,        // 2 PM
///     median: 120,     // Center line
///     percentile25: 100, // Lower bound of dark band
///     percentile75: 140, // Upper bound of dark band
///     percentile10: 80,  // Lower bound of light band
///     percentile90: 160  // Upper bound of light band
/// )
/// ```
///
/// This data structure is used to create area charts showing glucose
/// variability patterns across different times of day.
public struct HourlyStats: Equatable {
    /// The hour of day (0-23) these statistics represent
    let hour: Int
    /// The median (50th percentile) glucose value for this hour
    let median: Double
    /// The 25th percentile glucose value (lower quartile)
    let percentile25: Double
    /// The 75th percentile glucose value (upper quartile)
    let percentile75: Double
    /// The 10th percentile glucose value (lower whisker)
    let percentile10: Double
    /// The 90th percentile glucose value (upper whisker)
    let percentile90: Double
}

extension Stat.StateModel {
    /// Hourly percentile bands for the AGP chart.
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
                percentile25: StatChartUtils.percentile(0.25, of: values), // Lower quartile
                percentile75: StatChartUtils.percentile(0.75, of: values), // Upper quartile
                percentile10: StatChartUtils.percentile(0.10, of: values), // Lower whisker
                percentile90: StatChartUtils.percentile(0.90, of: values) // Upper whisker
            )
        }
    }
}
