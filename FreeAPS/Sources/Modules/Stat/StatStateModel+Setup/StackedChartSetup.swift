import CoreData
import Foundation

extension Stat {
    /// Represents a single data point in the glucose range distribution
    /// - hour: The hour of the day (0-23)
    /// - count: The percentage of readings in this range for the given hour (0-100)
    struct GlucoseRangeValue {
        let hour: Int
        let count: Double
    }

    /// Represents the distribution of glucose values within specific ranges for each hour
    ///
    /// This struct is used to visualize how glucose values are distributed across different
    /// ranges (e.g., low, target, high) throughout the day. Each range has a name and
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
    struct GlucoseRangeStats: Identifiable {
        let id = UUID()
        /// The name of the glucose range (e.g., "70-140", "<54")
        let name: String
        /// Array of hourly values containing percentages for this range
        let values: [GlucoseRangeValue]
    }
}

extension Stat.StateModel {
    /// Calculates range statistics for grouped glucose values
    /// - Parameter groupedValues: Dictionary with dates as keys and arrays of glucose readings as values
    /// - Returns: Dictionary with dates as keys and arrays of range statistics as values
    ///
    /// This function processes glucose readings grouped by date to calculate the distribution
    /// of values across different ranges for each hour of the day.
    func calculateRangeStats(
        for groupedValues: [Date: [GlucoseStored]]
    ) -> [Date: [Stat.GlucoseRangeStats]] {
        groupedValues.mapValues { values in
            calculateGlucoseRangeStats(from: values.map(\.objectID))
        }
    }

    /// Calculates the distribution of glucose values across different ranges for each hour
    /// - Parameter ids: Array of NSManagedObjectIDs for glucose readings
    /// - Returns: Array of GlucoseRangeStats containing percentage distributions
    ///
    /// The calculation process:
    /// 1. Groups readings by hour of day
    /// 2. Defines glucose ranges and their conditions
    /// 3. For each range and hour:
    ///    - Counts readings that fall within the range
    ///    - Calculates percentage of total readings in that range
    ///
    /// The results are used to create stacked area charts showing:
    /// - Distribution of glucose values across ranges
    /// - Patterns in glucose control throughout the day
    /// - Time spent in different ranges for each hour
    func calculateGlucoseRangeStats(from ids: [NSManagedObjectID]) -> [Stat.GlucoseRangeStats] {
        let calendar = Calendar.current

        // Group glucose values by hour
        let hourlyGroups = Dictionary(
            grouping: fetchGlucoseValues(from: ids),
            by: { calendar.component(.hour, from: $0.date ?? Date()) }
        )

        // Prepare hourly values for processing
        let hourlyValues = (0 ... 23).map { hour -> (hour: Int, values: [Double]) in
            let values = hourlyGroups[hour]?.compactMap { Double($0.glucose) } ?? []
            return (hour, values)
        }

        // Define glucose ranges and their conditions
        let ranges: [(name: String, filter: (Double) -> Bool)] = [
            ("<54", { [self] in $0 < Double(self.lowLimit - 20) }),
            ("54-70", { [self] in $0 >= Double(self.lowLimit - 20) && $0 < Double(self.lowLimit) }),
            ("70-140", { [self] in $0 >= Double(self.lowLimit) && $0 <= 140 }),
            ("140-180", { [self] in $0 > 140 && $0 <= Double(self.highLimit) }),
            ("180-200", { [self] in $0 > Double(self.highLimit) && $0 <= 200 }),
            ("200-220", { $0 > 200 && $0 <= 220 }),
            (">220", { $0 > 220 })
        ]

        // Calculate percentage distribution for each range
        return ranges.map { range in
            Stat.GlucoseRangeStats(
                name: range.name,
                values: hourlyValues.map { hour, values in
                    let total = Double(values.count)
                    let count = values.filter(range.filter).count
                    return Stat.GlucoseRangeValue(
                        hour: hour,
                        count: total > 0 ? Double(count) / total : 0
                    )
                }
            )
        }
    }
}
