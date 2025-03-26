import CoreData
import Foundation

/// Represents the distribution of glucose values within specific ranges for each hour.
///
/// This struct is used to visualize how glucose values are distributed across different
/// ranges (e.g., low, normal, high) throughout the day. Each range has a name and
/// corresponding hourly values showing the percentage of readings in that range.
///
/// Example ranges and their meanings:
/// - "<54": Urgent low
/// - "54-70": Low
/// - "70-140": Target range
/// - "140-180": High
/// - "180-200": Very high
/// - "200-220": Very high+
/// - ">220": Urgent high
///
/// Example usage:
/// ```swift
/// let range = GlucoseRangeStats(
///     name: "70-140",           // Target range
///     values: [
///         (hour: 8, count: 75), // 75% of readings at 8 AM were in range
///         (hour: 9, count: 80)  // 80% of readings at 9 AM were in range
///     ]
/// )
/// ```
///
/// This data structure is used to create stacked area charts showing the
/// distribution of glucose values across different ranges for each hour of the day.
public struct GlucoseRangeStats: Identifiable {
    /// The name of the glucose range (e.g., "70-140", "<54")
    let name: String

    /// Array of tuples containing the hour and percentage of readings in this range
    /// - hour: Hour of the day (0-23)
    /// - count: Percentage of readings in this range for the given hour (0-100)
    let values: [(hour: Int, count: Int)]

    /// Unique identifier for the range, derived from its name
    public var id: String { name }
}

extension Stat.StateModel {
    /// Calculates hourly glucose range distribution statistics.
    /// The calculation runs asynchronously using the CoreData context.
    ///
    /// The calculation works as follows:
    /// 1. Count unique days for each hour to handle missing data
    /// 2. For each glucose range and hour:
    ///    - Count readings in that range
    ///    - Calculate percentage based on number of days with readings
    ///
    /// Example:
    /// If we have data for 7 days and at 6:00 AM:
    /// - 3 days had readings in range 70-140
    /// - 2 days had readings in range 140-180
    /// - 2 day had a reading in range 180-200
    /// Then for 6:00 AM:
    /// - 70-140 = (3/7)*100 = 42.9%
    /// - 140-180 = (2/7)*100 = 28.6%
    /// - 180-200 = (2/7)*100 = 28.6%
    func calculateGlucoseRangeStatsForStackedChart(from ids: [NSManagedObjectID]) async {
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

            // Count unique days for each hour
            let daysPerHour = (0 ... 23).map { hour in
                let uniqueDays = Set(readings.compactMap { reading -> Date? in
                    guard let date = reading.date else { return nil }
                    if calendar.component(.hour, from: date) == hour {
                        return calendar.startOfDay(for: date)
                    }
                    return nil
                })
                return (hour: hour, days: uniqueDays.count)
            }

            // Define glucose ranges and their conditions
            // Ranges are processed from bottom to top in the stacked chart
            let ranges: [(name: String, condition: (Int) -> Bool)] = [
                ("<54", { g in g <= 54 }),
                ("54-\(self.timeInRangeType.bottomThreshold)", { g in g > 54 && g < self.timeInRangeType.bottomThreshold }),
                (
                    "\(self.timeInRangeType.bottomThreshold)-\(self.timeInRangeType.topThreshold)",
                    { g in g >= self.timeInRangeType.bottomThreshold && g <= self.timeInRangeType.topThreshold }
                ),
                ("\(self.timeInRangeType.topThreshold)-180", { g in g > self.timeInRangeType.topThreshold && g <= 180 }),
                ("180-200", { g in g > 180 && g <= 200 }),
                ("200-220", { g in g > 200 && g <= 220 }),
                (">220", { g in g > 220 })
            ]

            // Process each range to create the chart data
            return ranges.map { rangeName, condition in
                // Calculate values for each hour within this range
                let hourlyValues = (0 ... 23).map { hour in
                    let totalDaysForHour = Double(daysPerHour[hour].days)
                    // Skip if no data for this hour
                    guard totalDaysForHour > 0 else { return (hour: hour, count: 0) }

                    // Count readings that match the range condition for this hour
                    let readingsInRange = readings.filter { reading in
                        guard let date = reading.date else { return false }
                        return calendar.component(.hour, from: date) == hour &&
                            condition(Int(reading.glucose))
                    }.count

                    // Convert to percentage based on number of days with data
                    let percentage = (Double(readingsInRange) / totalDaysForHour) * 100.0
                    return (hour: hour, count: Int(percentage))
                }
                return GlucoseRangeStats(name: rangeName, values: hourlyValues)
            }
        }

        // Update stats on main thread
        await MainActor.run {
            self.glucoseRangeStats = stats
        }
    }
}
