import Foundation

/// A single glucose reading captured during a physio test
struct PhysioGlucoseReading: Codable {
    let date: Date
    let glucose: Int16
    let direction: String?

    /// Rate of change in mg/dL per minute (1st derivative)
    var rateOfChange: Double?

    /// Acceleration in mg/dL per minute per minute (2nd derivative)
    var acceleration: Double?
}

/// Helper to encode/decode glucose readings to/from Core Data binary field
enum PhysioGlucoseReadingCoder {
    static func encode(_ readings: [PhysioGlucoseReading]) -> Data? {
        try? JSONEncoder().encode(readings)
    }

    static func decode(_ data: Data?) -> [PhysioGlucoseReading] {
        guard let data = data else { return [] }
        return (try? JSONDecoder().decode([PhysioGlucoseReading].self, from: data)) ?? []
    }
}

/// Computed absorption metrics derived from a completed physio test
struct AbsorptionMetrics {
    /// Minutes from eating to first detectable BG rise
    let onsetDelay: Double
    /// Maximum rate of BG rise in mg/dL per minute
    let peakAbsorptionRate: Double
    /// Minutes from eating to peak absorption rate
    let timeToPeakRate: Double
    /// Minutes from eating to peak BG
    let timeToPeakBG: Double
    /// Peak BG value during test
    let peakGlucose: Double
    /// Total area under the curve above baseline (mg/dL * minutes)
    let totalAUC: Double
    /// Minutes from first rise to return to baseline
    let absorptionDuration: Double
    /// Baseline BG before test started
    let baselineGlucose: Double

    /// Computes metrics from a set of glucose readings, a baseline, and a meal time
    static func compute(
        readings: [PhysioGlucoseReading],
        baselineGlucose: Double,
        mealTime: Date
    ) -> AbsorptionMetrics? {
        guard readings.count >= 3 else { return nil }

        let sortedReadings = readings.sorted { $0.date < $1.date }

        // Threshold for "detectable rise" above baseline
        let riseThreshold = baselineGlucose + 3.0

        // Find onset: first reading after meal that exceeds threshold
        var onsetDate: Date?
        for reading in sortedReadings where reading.date > mealTime {
            if Double(reading.glucose) > riseThreshold {
                onsetDate = reading.date
                break
            }
        }

        let onsetDelay = onsetDate.map { $0.timeIntervalSince(mealTime) / 60.0 } ?? 0

        // Compute rates of change between consecutive readings
        var rates: [(date: Date, rate: Double, glucose: Double)] = []
        for i in 1 ..< sortedReadings.count {
            let dt = sortedReadings[i].date.timeIntervalSince(sortedReadings[i - 1].date) / 60.0
            guard dt > 0 else { continue }
            let dg = Double(sortedReadings[i].glucose) - Double(sortedReadings[i - 1].glucose)
            let rate = dg / dt
            rates.append((date: sortedReadings[i].date, rate: rate, glucose: Double(sortedReadings[i].glucose)))
        }

        // Peak absorption rate (max rate of rise)
        let peakRate = rates.max(by: { $0.rate < $1.rate })
        let peakAbsorptionRate = peakRate?.rate ?? 0
        let timeToPeakRate = (peakRate?.date.timeIntervalSince(mealTime) ?? 0) / 60.0

        // Peak glucose
        let peakReading = sortedReadings.max(by: { $0.glucose < $1.glucose })
        let peakGlucose = Double(peakReading?.glucose ?? 0)
        let timeToPeakBG = (peakReading?.date.timeIntervalSince(mealTime) ?? 0) / 60.0

        // AUC above baseline (trapezoidal integration)
        var totalAUC: Double = 0
        for i in 1 ..< sortedReadings.count {
            let dt = sortedReadings[i].date.timeIntervalSince(sortedReadings[i - 1].date) / 60.0
            let g1 = max(0, Double(sortedReadings[i - 1].glucose) - baselineGlucose)
            let g2 = max(0, Double(sortedReadings[i].glucose) - baselineGlucose)
            totalAUC += (g1 + g2) / 2.0 * dt
        }

        // Absorption duration: time from onset to return to near-baseline
        var returnDate: Date?
        if let onset = onsetDate, let peakDate = peakReading?.date {
            for reading in sortedReadings where reading.date > peakDate {
                if Double(reading.glucose) <= riseThreshold {
                    returnDate = reading.date
                    break
                }
            }
        }
        let absorptionDuration: Double
        if let onset = onsetDate, let ret = returnDate {
            absorptionDuration = ret.timeIntervalSince(onset) / 60.0
        } else if let onset = onsetDate, let last = sortedReadings.last {
            absorptionDuration = last.date.timeIntervalSince(onset) / 60.0
        } else {
            absorptionDuration = 0
        }

        return AbsorptionMetrics(
            onsetDelay: onsetDelay,
            peakAbsorptionRate: peakAbsorptionRate,
            timeToPeakRate: timeToPeakRate,
            timeToPeakBG: timeToPeakBG,
            peakGlucose: peakGlucose,
            totalAUC: totalAUC,
            absorptionDuration: absorptionDuration,
            baselineGlucose: baselineGlucose
        )
    }
}
