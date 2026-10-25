import Foundation

/// The last 24 hours of glucose as the watch gets them with every state, as the phone shows them: its values in the
/// display units and its colors. Compact: the first reading's time, then per reading the seconds since the one before
/// and the change in value, both as integers, and its color as 0xRRGGBB. In a binary property list a day of a 5-minute
/// CGM is 1 to 4 KB, of a 1-minute CGM 5 to 18 KB, the more the more distinct colors the dynamic scheme gives, so the
/// whole window goes every time and there is nothing to sync. The watch only unpacks them.
enum WatchGlucoseTrace {
    struct Reading: Equatable {
        let date: Date
        /// In the display units.
        let glucose: Double
        /// 0xRRGGBB
        let color: Int
    }

    static let startKey = "start"
    static let timesKey = "times"
    static let valuesKey = "values"
    static let colorsKey = "colors"
    /// The values are whole multiples of 1/scale: 1 for mg/dL, 10 for mmol/L's one decimal.
    static let scaleKey = "scale"

    /// Sorts the readings, oldest first; times are rounded to the second, values to 1/scale.
    static func encode(_ readings: [Reading], scale: Int) -> [String: Any] {
        let sorted = readings.sorted { $0.date < $1.date }
        let start = sorted.first.map { Int($0.date.timeIntervalSince1970.rounded()) } ?? 0
        var times: [Int] = []
        var values: [Int] = []
        var previousTime = start
        var previousValue = 0
        for reading in sorted {
            let time = Int(reading.date.timeIntervalSince1970.rounded())
            let value = Int((reading.glucose * Double(scale)).rounded())
            times.append(time - previousTime)
            values.append(value - previousValue)
            previousTime = time
            previousValue = value
        }
        return [startKey: start, timesKey: times, valuesKey: values, colorsKey: sorted.map(\.color), scaleKey: scale]
    }

    /// Oldest first; nil for anything that isn't a trace.
    static func decode(_ trace: [String: Any]) -> [Reading]? {
        guard let start = trace[startKey] as? Int,
              let times = trace[timesKey] as? [Int],
              let values = trace[valuesKey] as? [Int],
              let colors = trace[colorsKey] as? [Int],
              let scale = trace[scaleKey] as? Int, scale > 0,
              times.count == values.count, colors.count == times.count
        else { return nil }

        var time = start
        var value = 0
        return times.indices.map { index in
            time += times[index]
            value += values[index]
            return Reading(
                date: Date(timeIntervalSince1970: TimeInterval(time)),
                glucose: Double(value) / Double(scale),
                color: colors[index]
            )
        }
    }

    /// "#RRGGBB" as the phone writes its colors, as 0xRRGGBB; white for anything else.
    static func rgb(hex: String) -> Int {
        Int(hex.drop(while: { $0 == "#" }), radix: 16) ?? 0xFFFFFF
    }
}
