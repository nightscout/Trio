import Foundation

/// The last 24 hours of glucose as the watch gets them with every state: the first reading's time, then per reading
/// the seconds since the one before and the change in mg/dL. A day of a 5-minute CGM is about 1 KB in a binary
/// property list, of a 1-minute CGM about 6 KB, so the whole window goes every time and there is nothing to sync.
/// The watch converts the units and computes the colors itself.
enum WatchGlucoseTrace {
    struct Reading: Equatable {
        let date: Date
        /// mg/dL
        let glucose: Int
    }

    static let startKey = "start"
    static let timesKey = "times"
    static let valuesKey = "values"

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
        return [startKey: start, timesKey: times, valuesKey: values]
    }

    /// Oldest first; nil for anything that isn't a trace.
    static func decode(_ trace: [String: Any]) -> [Reading]? {
        guard let start = trace[startKey] as? Int,
              let times = trace[timesKey] as? [Int],
              let values = trace[valuesKey] as? [Int],
              times.count == values.count
        else { return nil }

        var time = start
        var value = 0
        return zip(times, values).map { timeDelta, valueDelta in
            time += timeDelta
            value += valueDelta
            return Reading(date: Date(timeIntervalSince1970: TimeInterval(time)), glucose: value)
        }
    }
}
