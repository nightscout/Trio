import CoreData
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
/// The data is used to create area charts with:
/// - A dark blue area for the interquartile range (25th-75th percentile)
/// - A light blue area for the wider range (10th-90th percentile)
/// - A solid blue line for the median
///
/// Example usage:
/// ```swift
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

extension Double {
    /// Helper property to check if a number is even
    var isEven: Bool {
        truncatingRemainder(dividingBy: 2) == 0
    }
}

extension Stat.StateModel {
    /// Calculates hourly statistics for grouped glucose values
    /// - Parameter groupedValues: Dictionary with dates as keys and arrays of glucose readings as values
    /// - Returns: Dictionary with dates as keys and arrays of hourly statistics as values
    ///
    /// This function processes glucose readings grouped by date to calculate hourly statistics
    /// for each group. The statistics include median and various percentiles that show
    /// the distribution of glucose values throughout the day.
    func calculateStats(
        for groupedValues: [Date: [GlucoseStored]]
    ) -> [Date: [HourlyStats]] {
        groupedValues.mapValues { values in
            calculateHourlyStats(from: values.map(\.objectID))
        }
    }

    /// Calculates detailed hourly statistics for a set of glucose readings
    /// - Parameter ids: Array of NSManagedObjectIDs for glucose readings
    /// - Returns: Array of HourlyStats containing percentile calculations for each hour
    ///
    /// The calculation process:
    /// 1. Groups readings by hour of day (0-23)
    /// 2. For each hour:
    ///    - Sorts glucose values
    ///    - Calculates median (50th percentile)
    ///    - Calculates 10th, 25th, 75th, and 90th percentiles
    ///
    /// These statistics are used to show:
    /// - The typical glucose range for each hour
    /// - The variability of glucose values
    /// - Patterns in glucose behavior throughout the day
    func calculateHourlyStats(from ids: [NSManagedObjectID]) -> [HourlyStats] {
        let calendar = Calendar.current

        // Fetch glucose values and group them by hour
        let hourlyGroups = Dictionary(
            grouping: fetchGlucoseValues(from: ids),
            by: { calendar.component(.hour, from: $0.date ?? Date()) }
        )

        // Calculate stats for each hour (0-23)
        return (0 ... 23).map { hour in
            let values = hourlyGroups[hour]?.compactMap { Double($0.glucose) }.sorted() ?? []
            guard !values.isEmpty else {
                return HourlyStats(hour: hour, median: 0, percentile25: 0, percentile75: 0, percentile10: 0, percentile90: 0)
            }

            // Calculate percentiles using array indices
            let count = values.count
            return HourlyStats(
                hour: hour,
                median: values[count * 50 / 100],
                percentile25: values[count * 25 / 100],
                percentile75: values[count * 75 / 100],
                percentile10: values[count * 10 / 100],
                percentile90: values[count * 90 / 100]
            )
        }
    }
}
