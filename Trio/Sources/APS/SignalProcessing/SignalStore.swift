import Foundation

/// Stores computed signal data for retrospective analysis and future learning phases (§11 Phase 1).
///
/// All signal outputs (Kalman-filtered BG, derivatives, residuals, Z-scores) are logged
/// to a local time-series store. This provides the foundation for Phase 5 (Adaptive Learning)
/// and immediate value for debugging and insight.
///
/// Data is persisted as JSON files managed by Trio's existing FileStorage system.
final class SignalStore {
    // MARK: - Configuration

    struct Config {
        /// Maximum number of signal entries to retain (at 5-min intervals, 288 = 24 hours)
        var maxEntries: Int = 2016 // 7 days at 5-min intervals

        /// Maximum number of daily Z-score entries to retain
        var maxDailyEntries: Int = 90 // 3 months
    }

    // MARK: - Signal Entry (per CGM reading)

    struct SignalEntry: JSON {
        let timestamp: Date

        // Kalman filter outputs
        let smoothedBG: Double
        let velocity: Double          // mg/dL per minute
        let acceleration: Double       // mg/dL per minute²
        let jerk: Double?             // mg/dL per minute³
        let bgUncertainty: Double
        let velocityUncertainty: Double
        let accelerationUncertainty: Double

        // Raw CGM for comparison
        let rawBG: Double

        // Residual data
        let residual: Double?
        let residualRate: Double?
        let estimatedCarbAbsorptionRate: Double?

        // Meal detection signal
        let mealDetectionConfidence: String // none/possible/likely/confirmed
        let accelerationSignalActive: Bool
        let jerkConfirmationActive: Bool
        let velocitySignalActive: Bool
    }

    // MARK: - Daily Z-Score Entry (per Garmin sync)

    struct DailyZScoreEntry: JSON {
        let date: Date
        let hrvZScore: Double?
        let restingHRZScore: Double?
        let sleepScoreZScore: Double?
        let sleepDurationZScore: Double?
        let deepSleepZScore: Double?
        let bodyBatteryZScore: Double?
        let stressConfidence: String
        let baselineSize: Int

        // Raw Garmin values for reference
        let hrvRMSSD: Double?
        let restingHR: Double?
        let sleepScore: Double?
        let sleepDurationMinutes: Double?
    }

    // MARK: - State

    private let config: Config
    private let storage: FileStorage
    private var signalEntries: [SignalEntry] = []
    private var dailyZScoreEntries: [DailyZScoreEntry] = []
    private var isDirty = false

    private static let signalFileName = "oref_signal_log.json"
    private static let zScoreFileName = "oref_zscore_log.json"

    init(storage: FileStorage, config: Config = Config()) {
        self.storage = storage
        self.config = config
        loadFromDisk()
    }

    // MARK: - Public API

    /// Log a signal entry from the CGM processing pipeline.
    func logSignal(_ entry: SignalEntry) {
        signalEntries.insert(entry, at: 0)
        if signalEntries.count > config.maxEntries {
            signalEntries.removeLast(signalEntries.count - config.maxEntries)
        }
        isDirty = true
    }

    /// Log a daily Z-score entry from the Garmin pipeline.
    func logDailyZScore(_ entry: DailyZScoreEntry) {
        // Remove any existing entry for the same calendar day
        let calendar = Calendar.current
        dailyZScoreEntries.removeAll { existing in
            calendar.isDate(existing.date, inSameDayAs: entry.date)
        }
        dailyZScoreEntries.insert(entry, at: 0)
        if dailyZScoreEntries.count > config.maxDailyEntries {
            dailyZScoreEntries.removeLast(dailyZScoreEntries.count - config.maxDailyEntries)
        }
        isDirty = true
    }

    /// Persist to disk. Call periodically or on app background.
    func save() {
        guard isDirty else { return }
        storage.save(signalEntries, as: SignalStore.signalFileName)
        storage.save(dailyZScoreEntries, as: SignalStore.zScoreFileName)
        isDirty = false
    }

    /// Recent signal entries (newest first).
    var recentSignals: [SignalEntry] {
        signalEntries
    }

    /// Recent Z-score entries (newest first).
    var recentZScores: [DailyZScoreEntry] {
        dailyZScoreEntries
    }

    /// Get signal entries for a time window.
    func signals(from start: Date, to end: Date) -> [SignalEntry] {
        signalEntries.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// Get the most recent signal entry.
    var latestSignal: SignalEntry? {
        signalEntries.first
    }

    /// Get the most recent Z-score entry.
    var latestZScore: DailyZScoreEntry? {
        dailyZScoreEntries.first
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        if let signals: [SignalEntry] = storage.retrieve(SignalStore.signalFileName, as: [SignalEntry].self) {
            signalEntries = signals
        }
        if let zScores: [DailyZScoreEntry] = storage.retrieve(
            SignalStore.zScoreFileName,
            as: [DailyZScoreEntry].self
        ) {
            dailyZScoreEntries = zScores
        }
    }
}
