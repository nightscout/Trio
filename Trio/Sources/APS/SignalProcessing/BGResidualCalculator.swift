import Foundation

/// Calculates the BG residual: the difference between actual BG and the BG
/// expected from insulin activity alone (§4.1, §4.2 of oref improvements spec).
///
/// Residual(t) = BG_actual(t) - BG_expected(t)
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

        /// Expected BG from IOB model alone
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

    /// Previous reading state for rolling delta calculation
    private var previousBG: Double?
    private var previousIOB: Double?
    private var previousTimestamp: Date?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    /// Update the residual calculation with a new Kalman-filtered BG reading and current IOB data.
    ///
    /// - Parameters:
    ///   - filteredBG: Kalman-filtered BG (mg/dL)
    ///   - iob: Current insulin on board (units)
    ///   - isf: Current insulin sensitivity factor (mg/dL per unit)
    ///   - cr: Current carb ratio (grams per unit), optional
    ///   - basalRate: Current basal rate (units/hr)
    ///   - timestamp: Time of reading
    /// - Returns: The residual entry for this reading
    @discardableResult
    func update(
        filteredBG: Double,
        iob: Double,
        isf: Double,
        cr: Double? = nil,
        basalRate: Double = 0,
        timestamp: Date
    ) -> ResidualEntry {
        let effectiveISF = max(isf, config.minISF)

        // Rolling 5-minute delta approach:
        // The insulin that "disappeared" between readings (previousIOB - currentIOB) is
        // the insulin that actually acted on BG during this interval.
        // expectedBG = previousBG - (previousIOB - currentIOB) * ISF
        // residual = actualBG - expectedBG (positive = unexplained rise, e.g. carbs)
        let expectedBG: Double
        if let prevBG = previousBG, let prevIOB = previousIOB {
            let iobConsumed = prevIOB - iob  // insulin that acted this interval
            expectedBG = prevBG - iobConsumed * effectiveISF
        } else {
            // First reading: no previous data, assume no residual
            expectedBG = filteredBG
        }

        // Update previous state for next iteration
        previousBG = filteredBG
        previousIOB = iob
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
        previousIOB = nil
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
