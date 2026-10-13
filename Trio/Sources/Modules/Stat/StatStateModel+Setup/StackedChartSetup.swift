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
    /// Share of readings in each glucose band per hour (0-100).
    static func makeGlucoseRangeStats(
        from readings: [GlucoseReading],
        bottom: Int,
        top: Int,
        highLimit: Int
    ) -> [GlucoseRangeStats] {
        let calendar = Calendar.current
        let byHour = Dictionary(grouping: readings) { calendar.component(.hour, from: $0.date) }

        return GlucoseBand.allCases.map { band in
            let hourly = (0 ... 23).map { hour -> (hour: Int, share: Double) in
                let hourReadings = byHour[hour, default: []]
                let inBand = hourReadings.count {
                    GlucoseBand.classify($0.value, bottom: bottom, top: top, highLimit: highLimit) == band
                }
                return (hour, Self.share(inBand, of: hourReadings.count))
            }
            return GlucoseRangeStats(band: band, values: hourly)
        }
    }

    private static func share(_ count: Int, of total: Int) -> Double {
        total > 0 ? Double(count) / Double(total) * 100 : 0
    }
}
