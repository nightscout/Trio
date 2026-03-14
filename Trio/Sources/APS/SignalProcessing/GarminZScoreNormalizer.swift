import Foundation

/// Normalizes Garmin health metrics to personal Z-scores against a rolling baseline (§6.1, §6.5).
///
/// HRV_deviation = (HRV_today - HRV_30day_mean) / HRV_30day_std_dev
///
/// Z-scores are the foundation for ISF modifiers in Phase 3. In Phase 1, they are
/// computed and logged for retrospective analysis without affecting dosing.
final class GarminZScoreNormalizer {
    // MARK: - Configuration

    struct Config {
        /// Number of days for the rolling baseline window
        var baselineDays: Int = 30

        /// Minimum number of data points required before Z-scores are considered valid
        var minimumDataPoints: Int = 7
    }

    // MARK: - Data Point

    struct DailyMetric: JSON {
        let date: Date
        let hrvRMSSD: Double?
        let restingHR: Double?
        let sleepScore: Double?
        let sleepDurationMinutes: Double?
        let deepSleepPercent: Double?
        let bodyBatteryMorning: Double?
    }

    // MARK: - Z-Score Output

    struct ZScoreSnapshot: JSON {
        let date: Date

        /// HRV Z-score (negative = below baseline = stressed/resistant)
        let hrvZScore: Double?

        /// Resting HR Z-score (positive = elevated = stressed/resistant)
        let restingHRZScore: Double?

        /// Sleep score Z-score (negative = below baseline = poor sleep)
        let sleepScoreZScore: Double?

        /// Sleep duration Z-score
        let sleepDurationZScore: Double?

        /// Deep sleep percentage Z-score
        let deepSleepZScore: Double?

        /// Body battery morning Z-score
        let bodyBatteryZScore: Double?

        /// Whether both HRV and resting HR confirm the stress signal (high confidence)
        var stressSignalConfidence: StressConfidence {
            guard let hrv = hrvZScore, let rhr = restingHRZScore else {
                if hrvZScore != nil || restingHRZScore != nil {
                    return .low
                }
                return .none
            }
            // HRV below baseline AND resting HR above baseline = high confidence stress
            if hrv < -1.0 && rhr > 1.0 {
                return .high
            } else if hrv < -0.5 && rhr > 0.5 {
                return .moderate
            } else if hrv < -0.5 || rhr > 0.5 {
                return .low
            }
            return .none
        }

        /// Number of data points in the baseline used for these Z-scores
        let baselineSize: Int
    }

    enum StressConfidence: String, Codable {
        case none
        case low
        case moderate
        case high
    }

    // MARK: - State

    private let config: Config

    /// Rolling baseline of daily metrics, newest first
    private(set) var baseline: [DailyMetric] = []

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    /// Add a new daily metric and compute Z-scores.
    /// Call once per day after Garmin overnight sync.
    func addDailyMetric(_ metric: DailyMetric) -> ZScoreSnapshot {
        // Remove any existing entry for the same calendar day
        let calendar = Calendar.current
        baseline.removeAll { existing in
            calendar.isDate(existing.date, inSameDayAs: metric.date)
        }

        // Insert newest first
        baseline.insert(metric, at: 0)

        // Trim to baseline window
        let cutoff = calendar.date(byAdding: .day, value: -config.baselineDays, to: metric.date) ?? metric.date
        baseline.removeAll { $0.date < cutoff }

        return computeZScores(for: metric)
    }

    /// Compute Z-scores for a given metric against the current baseline.
    func computeZScores(for metric: DailyMetric) -> ZScoreSnapshot {
        let hrvValues = baseline.compactMap(\.hrvRMSSD)
        let rhrValues = baseline.compactMap(\.restingHR)
        let sleepScoreValues = baseline.compactMap(\.sleepScore)
        let sleepDurationValues = baseline.compactMap(\.sleepDurationMinutes)
        let deepSleepValues = baseline.compactMap(\.deepSleepPercent)
        let bbValues = baseline.compactMap(\.bodyBatteryMorning)

        return ZScoreSnapshot(
            date: metric.date,
            hrvZScore: zScore(value: metric.hrvRMSSD, from: hrvValues),
            restingHRZScore: zScore(value: metric.restingHR, from: rhrValues),
            sleepScoreZScore: zScore(value: metric.sleepScore, from: sleepScoreValues),
            sleepDurationZScore: zScore(value: metric.sleepDurationMinutes, from: sleepDurationValues),
            deepSleepZScore: zScore(value: metric.deepSleepPercent, from: deepSleepValues),
            bodyBatteryZScore: zScore(value: metric.bodyBatteryMorning, from: bbValues),
            baselineSize: baseline.count
        )
    }

    /// Build a daily metric from a GarminContextSnapshot.
    func metricFromSnapshot(_ snapshot: GarminContextSnapshot) -> DailyMetric {
        let deepSleepPct: Double?
        if let deep = snapshot.deepSleepDurationInSeconds, let total = snapshot.sleepDurationInSeconds, total > 0 {
            deepSleepPct = Double(deep) / Double(total) * 100.0
        } else {
            deepSleepPct = nil
        }

        return DailyMetric(
            date: snapshot.queryTime,
            hrvRMSSD: snapshot.lastNightAvg.map(Double.init),
            restingHR: snapshot.restingHeartRateInBeatsPerMinute.map(Double.init),
            sleepScore: snapshot.sleepScoreValue.map(Double.init),
            sleepDurationMinutes: snapshot.totalSleepMinutes.map(Double.init),
            deepSleepPercent: deepSleepPct,
            bodyBatteryMorning: snapshot.bodyBatteryAtWake.map(Double.init)
        )
    }

    /// Load baseline from persisted data
    func loadBaseline(_ metrics: [DailyMetric]) {
        baseline = metrics.sorted { $0.date > $1.date }
        let cutoff = Calendar.current.date(byAdding: .day, value: -config.baselineDays, to: Date()) ?? Date()
        baseline.removeAll { $0.date < cutoff }
    }

    // MARK: - Z-Score Calculation

    private func zScore(value: Double?, from population: [Double]) -> Double? {
        guard let v = value, population.count >= config.minimumDataPoints else {
            return nil
        }

        let mean = population.reduce(0, +) / Double(population.count)
        let variance = population.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(population.count)
        let stdDev = sqrt(variance)

        // Avoid division by zero - if no variance, Z-score is 0
        guard stdDev > 0.001 else { return 0 }

        return (v - mean) / stdDev
    }
}
