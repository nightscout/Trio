import CoreData
import Foundation

/// Represents the distribution of glucose values within specific ranges for each hour.
///
/// This struct is used to visualize how glucose values are distributed across different
/// ranges (e.g., low, normal, high) throughout the day. Each range has a name and
/// corresponding hourly values showing the percentage of readings in that range.
///
/// This data structure is used to create stacked area charts showing the
/// distribution of glucose values across different ranges for each hour of the day.
struct GlucoseRangeStats: Identifiable {
    let band: GlucoseBand

    /// Array of tuples containing the hour and percentage of readings in this range
    /// - hour: Hour of the day (0-23)
    /// - share: Percentage of readings in this range for the given hour (0-100)
    let values: [(hour: Int, share: Double)]

    var id: GlucoseBand { band }
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
        let bottom = timeInRangeType.bottomThreshold
        let top = timeInRangeType.topThreshold
        let high = Int(highLimit)

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

            let validReadings = readings.compactMap { reading -> (date: Date, glucose: Int)? in
                guard let date = reading.date else { return nil }
                return (date, Int(reading.glucose))
            }

            let byHour = Dictionary(grouping: validReadings) { calendar.component(.hour, from: $0.date) }

            // Process each range to create the chart data
            return GlucoseBand.allCases.map { band in
                let hourly = (0 ... 23).map { hour -> (hour: Int, share: Double) in
                    let hourReadings = byHour[hour, default: []]
                    let inBand = hourReadings.count {
                        GlucoseBand.classify(
                            $0.glucose,
                            bottom: bottom,
                            top: top,
                            highLimit: high
                        ) == band
                    }
                    return (hour, Self.share(inBand, of: hourReadings.count))
                }

                return GlucoseRangeStats(band: band, values: hourly)
            }
        }

        // Update stats on main thread
        await MainActor.run {
            self.glucoseRangeStats = stats
        }
    }

    private static func share(_ count: Int, of total: Int) -> Double {
        total > 0 ? Double(count) / Double(total) * 100 : 0
    }
}
