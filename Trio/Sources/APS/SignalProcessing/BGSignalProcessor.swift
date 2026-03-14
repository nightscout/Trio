import Foundation

/// Processes CGM readings through the adaptive Kalman filter and implements
/// the signal hierarchy for meal detection (§4.4, §4.5 of oref improvements spec).
///
/// Signal Hierarchy for Meal Detection:
/// - Primary: Acceleration positive and sustained (~10 min lead over velocity alone)
/// - Confirmatory: Jerk positive for 2+ consecutive 5-min readings
/// - Tertiary: Velocity crossing threshold (current UAM behavior, retained as fallback)
final class BGSignalProcessor {
    // MARK: - Configuration

    struct Config {
        /// Minimum positive acceleration (mg/dL/min²) to trigger primary meal signal
        var accelerationThreshold: Double = 0.05

        /// Minimum sustained acceleration duration (minutes) for primary signal
        var accelerationSustainedMinutes: Double = 10.0

        /// Number of consecutive positive jerk readings required for confirmation
        var jerkConsecutiveRequired: Int = 2

        /// Velocity threshold (mg/dL/min) for tertiary UAM-style detection
        var velocityThreshold: Double = 0.5

        /// Maximum number of recent readings to retain for history
        var maxHistoryCount: Int = 72 // 6 hours at 5-min intervals
    }

    // MARK: - Meal Detection Signal

    struct MealSignal {
        /// Whether the primary signal (sustained positive acceleration) is active
        let accelerationSignal: Bool

        /// Whether the confirmatory signal (consecutive positive jerk) is active
        let jerkConfirmation: Bool

        /// Whether the tertiary signal (velocity above threshold) is active
        let velocitySignal: Bool

        /// Composite meal detection confidence: .none, .possible, .likely, .confirmed
        var confidence: MealDetectionConfidence {
            if accelerationSignal && jerkConfirmation {
                return .confirmed
            } else if accelerationSignal {
                return .likely
            } else if velocitySignal {
                return .possible
            }
            return .none
        }
    }

    enum MealDetectionConfidence: String, Codable {
        case none
        case possible   // velocity only (current UAM equivalent)
        case likely     // sustained acceleration
        case confirmed  // acceleration + jerk confirmation
    }

    // MARK: - State

    private let kalmanFilter: AdaptiveKalmanFilter
    private let config: Config

    /// Rolling history of filter outputs, newest first
    private(set) var history: [AdaptiveKalmanFilter.FilterOutput] = []

    /// Count of consecutive positive jerk readings
    private var consecutivePositiveJerkCount: Int = 0

    /// Timestamp when acceleration first went positive (for sustained check)
    private var accelerationPositiveSince: Date?

    init(
        kalmanConfig: AdaptiveKalmanFilter.Config = AdaptiveKalmanFilter.Config(),
        config: Config = Config()
    ) {
        self.kalmanFilter = AdaptiveKalmanFilter(config: kalmanConfig)
        self.config = config
    }

    // MARK: - Public API

    /// Process a new CGM reading and return the enriched signal output.
    @discardableResult
    func processReading(glucose: Double, at timestamp: Date) -> SignalOutput {
        let filterOutput = kalmanFilter.update(glucose: glucose, at: timestamp)

        // Update history (newest first)
        history.insert(filterOutput, at: 0)
        if history.count > config.maxHistoryCount {
            history.removeLast(history.count - config.maxHistoryCount)
        }

        // Update jerk tracking
        if let jerk = filterOutput.jerk, jerk > 0 {
            consecutivePositiveJerkCount += 1
        } else {
            consecutivePositiveJerkCount = 0
        }

        // Update acceleration tracking
        if filterOutput.acceleration > config.accelerationThreshold {
            if accelerationPositiveSince == nil {
                accelerationPositiveSince = timestamp
            }
        } else {
            accelerationPositiveSince = nil
        }

        let mealSignal = evaluateMealSignal(output: filterOutput, at: timestamp)

        return SignalOutput(
            filter: filterOutput,
            mealSignal: mealSignal,
            timestamp: timestamp
        )
    }

    /// Reset the processor (e.g. on sensor change)
    func reset() {
        kalmanFilter.reset()
        history.removeAll()
        consecutivePositiveJerkCount = 0
        accelerationPositiveSince = nil
    }

    /// Current filter state, if available
    var currentOutput: AdaptiveKalmanFilter.FilterOutput? {
        history.first
    }

    // MARK: - Meal Signal Evaluation

    private func evaluateMealSignal(
        output: AdaptiveKalmanFilter.FilterOutput,
        at timestamp: Date
    ) -> MealSignal {
        // Primary: sustained positive acceleration
        let accelerationActive: Bool
        if let since = accelerationPositiveSince {
            let sustainedMinutes = timestamp.timeIntervalSince(since) / 60.0
            accelerationActive = sustainedMinutes >= config.accelerationSustainedMinutes
        } else {
            accelerationActive = false
        }

        // Confirmatory: consecutive positive jerk
        let jerkConfirmed = consecutivePositiveJerkCount >= config.jerkConsecutiveRequired

        // Tertiary: velocity above threshold
        let velocityActive = output.velocity > config.velocityThreshold

        return MealSignal(
            accelerationSignal: accelerationActive,
            jerkConfirmation: jerkConfirmed,
            velocitySignal: velocityActive
        )
    }

    // MARK: - Output

    struct SignalOutput {
        let filter: AdaptiveKalmanFilter.FilterOutput
        let mealSignal: MealSignal
        let timestamp: Date
    }
}
