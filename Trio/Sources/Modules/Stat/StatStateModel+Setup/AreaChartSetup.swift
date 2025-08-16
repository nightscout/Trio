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

extension Double {
    var isEven: Bool {
        truncatingRemainder(dividingBy: 2) == 0
    }
}

extension Stat.StateModel {
    /// Calculates hourly statistical values (median, percentiles) from glucose readings.
    /// The calculation runs asynchronously using the CoreData context.
    ///
    /// The calculation works as follows:
    /// 1. Group readings by hour of day (0-23)
    /// 2. For each hour:
    ///    - Sort glucose values
    ///    - Calculate median (50th percentile)
    ///    - Calculate 10th, 25th, 75th, and 90th percentiles
    ///
    /// Example:
    /// For readings at 6:00 AM across multiple days:
    /// ```
    /// Readings: [80, 100, 120, 140, 160, 180, 200]
    /// Results:
    /// - 10th percentile: 84 (lower whisker)
    /// - 25th percentile: 110 (lower band)
    /// - median: 140 (center line)
    /// - 75th percentile: 170 (upper band)
    /// - 90th percentile: 196 (upper whisker)
    /// ```
    ///
    /// The resulting statistics are used to show:
    /// - A dark blue area for the interquartile range (25th-75th percentile)
    /// - A light blue area for the wider range (10th-90th percentile)
    /// - A solid blue line for the median
    func calculateHourlyStatsForGlucoseAreaChart(from ids: [NSManagedObjectID]) async {
        let taskContext = CoreDataStack.shared.newTaskContext()

        let calendar = Calendar.current

        let stats = await taskContext.perform {
            // Convert IDs to GlucoseStored objects using the context
            let readings = ids.compactMap { id -> GlucoseStored? in
                do {
                    return try taskContext.existingObject(with: id) as? GlucoseStored
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Error fetching glucose: \(error)")
                    return nil
                }
            }

            // Group readings by hour of day (0-23)
            // Example: [8: [reading1, reading2], 9: [reading3, reading4, reading5], ...]
            let groupedByHour = Dictionary(grouping: readings) { reading in
                calendar.component(.hour, from: reading.date ?? Date())
            }

            // Process each hour of the day (0-23)
            return (0 ... 23).map { hour in
                // Get all readings for this hour (or empty if none)
                let readings = groupedByHour[hour] ?? []

                // Extract and sort glucose values for percentile calculations
                // Example: [100, 120, 130, 140, 150, 160, 180]
                let values = readings.map { Double($0.glucose) }.sorted()
                let count = Double(values.count)

                // Handle hours with no readings
                guard !values.isEmpty else {
                    return HourlyStats(
                        hour: hour,
                        median: 0,
                        percentile25: 0,
                        percentile75: 0,
                        percentile10: 0,
                        percentile90: 0
                    )
                }

                // Calculate median
                // For even count: average of two middle values
                // For odd count: middle value
                let median = count.isEven ?
                    (values[Int(count / 2) - 1] + values[Int(count / 2)]) / 2 :
                    values[Int(count / 2)]

                // Create statistics object with all percentiles
                // Index calculation: multiply count by desired percentile (0.25 for 25th)
                return HourlyStats(
                    hour: hour,
                    median: median,
                    percentile25: values[Int(count * 0.25)], // Lower quartile
                    percentile75: values[Int(count * 0.75)], // Upper quartile
                    percentile10: values[Int(count * 0.10)], // Lower whisker
                    percentile90: values[Int(count * 0.90)] // Upper whisker
                )
            }
        }

        // Update stats on main thread
        await MainActor.run {
            self.hourlyStats = stats
        }
    }
}
