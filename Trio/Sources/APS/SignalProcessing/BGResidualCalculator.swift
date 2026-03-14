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

    /// The reference BG at the start of residual tracking (or last reset point)
    private var referenceBG: Double?
    private var referenceTimestamp: Date?

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

        // Expected BG: current BG should be moving toward target based on IOB
        // The expected BG delta from IOB is: -IOB * ISF (negative because insulin lowers BG)
        // We track the cumulative expected change from a reference point
        let expectedBG: Double
        if let refBG = referenceBG, let refTime = referenceTimestamp {
            // Expected BG = reference BG - (IOB effect since reference)
            // Simplified: at any point, IOB * ISF tells us how much BG *will* drop from current active insulin
            // So expected BG trajectory without carbs = current_BG + IOB_change * ISF
            // But we want: what would BG be if only insulin were acting?
            // expectedBG = referenceBG - accumulated_insulin_effect
            // For the 5-min window approach: expectedBG = previousBG - (insulin_activity * ISF * dt)
            // Using IOB directly: the expected BG given IOB = last_known_BG_without_carbs - IOB * ISF
            _ = refTime // used for future time-decay modeling
            expectedBG = refBG - iob * effectiveISF
        } else {
            // First reading: set reference and assume no residual
            referenceBG = filteredBG
            referenceTimestamp = timestamp
            expectedBG = filteredBG
        }

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
        referenceBG = bg
        referenceTimestamp = timestamp
        smoothedResidualRate = nil
    }

    /// Reset all state
    func reset() {
        history.removeAll()
        referenceBG = nil
        referenceTimestamp = nil
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
