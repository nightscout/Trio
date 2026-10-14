import Foundation

struct GlucoseRangeStats: Identifiable {
    let band: GlucoseBand

    let values: [(hour: Int, share: Double)]

    var id: GlucoseBand { band }
}

extension Stat.StateModel {
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
