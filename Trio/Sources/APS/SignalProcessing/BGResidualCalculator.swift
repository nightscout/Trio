import Foundation

/// Calculates the BG residual: the difference between actual BG and the BG
/// expected from insulin activity alone (§4.1, §4.2 of oref improvements spec).
///
/// Residual(t) = BG_actual(t) - BG_expected(t)
///
/// Uses oref's `activity` field from the IOB calculation, which represents the
/// instantaneous rate of insulin action derived from complete pump history.
/// This captures ALL insulin delivery: scheduled basals, temp basals, SMBs,
/// manual boluses, corrections, and external insulin.
///
/// A positive and growing residual indicates carbohydrate absorption (or other
/// BG-raising factors) that are not explained by the insulin model.
///
/// From the residual, we can estimate carb absorption rate:
///   Carb Absorption Rate (g/min) = (dResidual/dt) / ISF × CR
final class BGResidualCalculator {
    // MARK: - Configuration

    struct Config {
        /// Maximum residual history entries to retain
        var maxHistoryCount: Int = 72

        /// Minimum ISF value to avoid division by zero (mg/dL per unit)
        var minISF: Double = 5.0

        /// EMA alpha for smoothing the residual rate of change
        var residualRateEMA: Double = 0.3
    }

    // MARK: - Residual Entry

    struct ResidualEntry {
        let timestamp: Date

        /// Actual BG from CGM (Kalman-filtered)
        let actualBG: Double

        /// Expected BG from insulin activity model alone
        let expectedBG: Double

        /// Residual = actual - expected
        var residual: Double { actualBG - expectedBG }

        /// Rate of change of residual (mg/dL per minute), nil for first entry
        let residualRate: Double?

        /// Estimated carb absorption rate (g/min), nil if ISF/CR not available
        let estimatedCarbAbsorptionRate: Double?
    }

    // MARK: - State

    private let config: Config
    private(set) var history: [ResidualEntry] = []
    private var smoothedResidualRate: Double?

    /// Previous reading state for rolling calculation
    private var previousBG: Double?
    private var previousTimestamp: Date?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    /// Update the residual calculation with a new Kalman-filtered BG reading and current insulin activity.
    ///
    /// - Parameters:
    ///   - filteredBG: Kalman-filtered BG (mg/dL)
    ///   - activity: Insulin activity from oref IOB calculation (units/5min). This is the rate at
    ///     which insulin is acting on BG, derived from complete pump history including all delivery
    ///     types (basals, temps, boluses, SMBs, external insulin).
    ///   - isf: Current insulin sensitivity factor (mg/dL per unit)
    ///   - cr: Current carb ratio (grams per unit), optional
    ///   - timestamp: Time of reading
    /// - Returns: The residual entry for this reading
    @discardableResult
    func update(
        filteredBG: Double,
        activity: Double,
        isf: Double,
        cr: Double? = nil,
        timestamp: Date
    ) -> ResidualEntry {
        let effectiveISF = max(isf, config.minISF)

        // Activity-based approach:
        // oref's `activity` (units/5min) represents the insulin being consumed right now,
        // derived from ALL pump history (basals, temps, boluses, SMBs, external insulin).
        // Expected BG change = -activity * ISF (insulin lowers BG)
        // expectedBG = previousBG - activity * ISF
        // residual = actualBG - expectedBG (positive = unexplained rise, e.g. carbs)
        let expectedBG: Double
        if let prevBG = previousBG, let prevTime = previousTimestamp {
            // Scale activity by actual interval vs the 5-min convention
            let dtMinutes = timestamp.timeIntervalSince(prevTime) / 60.0
            let scaledActivity = activity * (dtMinutes / 5.0)
            expectedBG = prevBG - scaledActivity * effectiveISF
        } else {
            // First reading: no previous data, assume no residual
            expectedBG = filteredBG
        }

        // Update previous state for next iteration
        previousBG = filteredBG
        previousTimestamp = timestamp

        // Calculate residual rate from previous entry
        var residualRate: Double?
        let currentResidual = filteredBG - expectedBG

        if let lastEntry = history.first {
            let dtMinutes = timestamp.timeIntervalSince(lastEntry.timestamp) / 60.0
            if dtMinutes > 0 {
                let rawRate = (currentResidual - lastEntry.residual) / dtMinutes

                // Smooth the rate with EMA
                if let prevSmoothed = smoothedResidualRate {
                    smoothedResidualRate = config.residualRateEMA * rawRate +
                        (1 - config.residualRateEMA) * prevSmoothed
                } else {
                    smoothedResidualRate = rawRate
                }
                residualRate = smoothedResidualRate
            }
        }

        // Estimate carb absorption rate if we have CR and a residual rate
        var carbAbsorptionRate: Double?
        if let rate = residualRate, let carbRatio = cr, rate > 0 {
            // Carb Absorption Rate (g/min) = (dResidual/dt) / ISF × CR
            // The residual rate is in mg/dL per minute
            // ISF is mg/dL per unit, CR is grams per unit
            // So: (mg/dL/min) / (mg/dL/unit) * (g/unit) = g/min
            carbAbsorptionRate = (rate / effectiveISF) * carbRatio
        }

        let entry = ResidualEntry(
            timestamp: timestamp,
            actualBG: filteredBG,
            expectedBG: expectedBG,
            residualRate: residualRate,
            estimatedCarbAbsorptionRate: carbAbsorptionRate
        )

        // Update history (newest first)
        history.insert(entry, at: 0)
        if history.count > config.maxHistoryCount {
            history.removeLast(history.count - config.maxHistoryCount)
        }

        return entry
    }

    /// Reset reference point (e.g. after meal is fully absorbed, or when residual returns to ~0)
    func resetReference(bg: Double, at timestamp: Date) {
        previousBG = bg
        previousTimestamp = timestamp
        smoothedResidualRate = nil
    }

    /// Reset all state
    func reset() {
        history.removeAll()
        previousBG = nil
        previousTimestamp = nil
        smoothedResidualRate = nil
    }

    /// Current residual value, if available
    var currentResidual: Double? {
        history.first?.residual
    }

    /// Current smoothed residual rate (mg/dL per minute)
    var currentResidualRate: Double? {
        smoothedResidualRate
    }

    /// Current estimated carb absorption rate (g/min)
    var currentCarbAbsorptionRate: Double? {
        history.first?.estimatedCarbAbsorptionRate
    }
}
