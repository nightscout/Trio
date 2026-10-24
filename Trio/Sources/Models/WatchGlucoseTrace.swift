import Foundation

/// The last 24 hours of glucose as the watch gets them with every state: the first reading's time, then per reading
/// the seconds since the one before and the change in mg/dL. A day of a 5-minute CGM is about 1 KB in a binary
/// property list, of a 1-minute CGM about 6 KB, so the whole window goes every time and there is nothing to sync.
/// Under the dynamic color scheme each reading's color as the phone computed it goes too; under the static one the
/// watch colors by the range the state carries.
enum WatchGlucoseTrace {
    struct Reading: Equatable {
        let date: Date
        /// mg/dL
        let glucose: Int
        /// 0xRRGGBB, the phone's color under the dynamic scheme; nil under the static one.
        var color: Int? = nil
    }

    static let startKey = "start"
    static let timesKey = "times"
    static let valuesKey = "values"
    static let colorsKey = "colors"

    /// Sorts the readings, oldest first; times are rounded to the second.
    static func encode(_ readings: [Reading]) -> [String: Any] {
        let sorted = readings.sorted { $0.date < $1.date }
        let start = sorted.first.map { Int($0.date.timeIntervalSince1970.rounded()) } ?? 0
        var times: [Int] = []
        var values: [Int] = []
        var previousTime = start
        var previousValue = 0
        for reading in sorted {
            let time = Int(reading.date.timeIntervalSince1970.rounded())
            times.append(time - previousTime)
            values.append(reading.glucose - previousValue)
            previousTime = time
            previousValue = reading.glucose
        }
        var trace: [String: Any] = [startKey: start, timesKey: times, valuesKey: values]
        let colors = sorted.compactMap(\.color)
        if !colors.isEmpty, colors.count == sorted.count { trace[colorsKey] = colors }
        return trace
    }

    /// Oldest first; nil for anything that isn't a trace.
    static func decode(_ trace: [String: Any]) -> [Reading]? {
        guard let start = trace[startKey] as? Int,
              let times = trace[timesKey] as? [Int],
              let values = trace[valuesKey] as? [Int],
              times.count == values.count
        else { return nil }
        let colors = trace[colorsKey] as? [Int]
        guard colors == nil || colors?.count == times.count else { return nil }

        var time = start
        var value = 0
        return zip(times, values).enumerated().map { index, deltas in
            time += deltas.0
            value += deltas.1
            return Reading(date: Date(timeIntervalSince1970: TimeInterval(time)), glucose: value, color: colors?[index])
        }
    }
}
