import Foundation

/// Phase 3: Daily State Vector & Static Modifiers
///
/// Computes ISF/CR/basal modifiers from Garmin Z-scores (HRV, sleep, exercise).
/// When the toggle is OFF, modifiers are computed and logged but not applied to oref.
/// When ON, they modify ISF/CR inputs to the oref loop.
///
/// Reference: oref improvements §6, §7

final class DailyStateVector {
    // MARK: - Configuration

    struct Config {
        /// HRV Z-score to ISF modifier scaling factor
        /// e.g., HRV 1 SD below normal → -5% ISF
        var hrvISFScale: Double = 0.05
        /// Maximum ISF modifier from HRV alone
        var hrvMaxModifier: Double = 0.15

        /// Sleep score thresholds and modifiers
        var poorSleepThreshold: Double = 50.0      // sleep score below this = poor
        var fairSleepThreshold: Double = 65.0
        var poorSleepISFModifier: Double = -0.15   // 15% more resistant
        var fairSleepISFModifier: Double = -0.08
        /// Sleep modifier decay: fraction remaining per hour after wake
        var sleepModifierDecayPerHour: Double = 0.06

        /// Body battery thresholds
        var lowBatteryThreshold: Double = 30.0
        var lowBatteryISFModifier: Double = -0.10

        /// Resting HR elevation thresholds
        var rhrElevationThreshold: Double = 1.0    // Z-score threshold
        var rhrISFScale: Double = 0.03

        /// Single modifier cap (no individual modifier > this)
        var singleModifierCap: Double = 0.30
        /// Aggregate modifier cap (total net ISF change capped)
        var aggregateModifierCap: Double = 0.40
    }

    // MARK: - Output

    /// The computed daily state vector output
    struct StateVectorOutput: Codable {
        let timestamp: Date

        // Individual modifiers (negative = more resistant, positive = more sensitive)
        let hrvModifier: Double?
        let sleepModifier: Double?
        let bodyBatteryModifier: Double?
        let rhrModifier: Double?

        // Aggregate
        let netISFModifier: Double   // Combined, capped
        let netCRModifier: Double    // Derived from ISF modifier
        let netBasalModifier: Double // For dawn phenomenon adjustment

        // Confidence
        let confidence: StateConfidence

        // Input data used
        let hrvZScore: Double?
        let sleepScore: Double?
        let bodyBattery: Double?
        let rhrZScore: Double?
        let hoursAwake: Double?

        // Explanation string for UI
        let explanation: String
    }

    enum StateConfidence: String, Codable {
        case high = "high"       // HRV + RHR both confirm
        case moderate = "moderate" // One strong signal
        case low = "low"         // Limited data
        case none = "none"       // No Garmin data
    }

    // MARK: - State

    private var config: Config
    private(set) var latestOutput: StateVectorOutput?
    private var lastComputeDate: Date?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Compute State Vector

    /// Compute the daily state vector from the latest Z-scores and Garmin data.
    /// Called after Garmin overnight sync and periodically throughout the day.
    func compute(
        hrvZScore: Double?,
        rhrZScore: Double?,
        sleepScore: Double?,
        sleepDurationMinutes: Double?,
        bodyBattery: Double?,
        stressConfidence: String?,
        hoursAwake: Double? = nil
    ) -> StateVectorOutput {
        var explanations: [String] = []

        // 1. HRV modifier
        let hrvMod: Double?
        if let hrv = hrvZScore {
            // Negative HRV Z-score = stressed = more resistant
            // hrvISFScale of 0.05 means 1 SD below → -5% ISF
            let raw = hrv * config.hrvISFScale
            hrvMod = clampSingle(raw)
            if abs(raw) > 0.02 {
                let direction = raw < 0 ? "lower" : "higher"
                explanations.append("HRV \(String(format: "%.1f", hrv)) SD → \(direction) sensitivity")
            }
        } else {
            hrvMod = nil
        }

        // 2. Sleep modifier (decays through the day)
        let sleepMod: Double?
        if let score = sleepScore {
            let baseMod: Double
            if score < config.poorSleepThreshold {
                baseMod = config.poorSleepISFModifier
                explanations.append("Poor sleep (\(Int(score))) → reduced sensitivity")
            } else if score < config.fairSleepThreshold {
                baseMod = config.fairSleepISFModifier
                explanations.append("Fair sleep (\(Int(score))) → slightly reduced sensitivity")
            } else {
                baseMod = 0
            }

            // Apply decay based on hours awake
            if let hours = hoursAwake, hours > 0, baseMod != 0 {
                let decayFactor = max(0, 1.0 - (hours * config.sleepModifierDecayPerHour))
                sleepMod = clampSingle(baseMod * decayFactor)
            } else {
                sleepMod = clampSingle(baseMod)
            }
        } else {
            sleepMod = nil
        }

        // 3. Body battery modifier
        let bbMod: Double?
        if let bb = bodyBattery {
            if bb < config.lowBatteryThreshold {
                let severity = (config.lowBatteryThreshold - bb) / config.lowBatteryThreshold
                bbMod = clampSingle(config.lowBatteryISFModifier * severity)
                explanations.append("Low body battery (\(Int(bb))) → reduced sensitivity")
            } else {
                bbMod = 0
            }
        } else {
            bbMod = nil
        }

        // 4. Resting HR modifier
        let rhrMod: Double?
        if let rhr = rhrZScore {
            // Positive RHR Z-score = elevated = stressed = more resistant
            if rhr > config.rhrElevationThreshold {
                let raw = -(rhr - config.rhrElevationThreshold) * config.rhrISFScale
                rhrMod = clampSingle(raw)
                explanations.append("Elevated RHR → reduced sensitivity")
            } else if rhr < -1.0 {
                // Lower than normal RHR = good recovery
                rhrMod = clampSingle(0.03) // Slight sensitivity boost
            } else {
                rhrMod = 0
            }
        } else {
            rhrMod = nil
        }

        // Aggregate all modifiers
        let modifiers = [hrvMod, sleepMod, bbMod, rhrMod].compactMap { $0 }
        let rawNet = modifiers.reduce(0, +)
        let netISF = max(-config.aggregateModifierCap, min(config.aggregateModifierCap, rawNet))

        // CR modifier tracks ISF modifier (more resistant → need more insulin per carb)
        let netCR = netISF * 0.8 // CR is slightly less affected than ISF

        // Basal modifier: only from sleep (dawn phenomenon amplification)
        let netBasal = (sleepMod ?? 0) * 0.5 // Half the sleep effect on basal

        // Confidence assessment
        let confidence: StateConfidence
        if let hrv = hrvZScore, let rhr = rhrZScore,
           hrv < -1.0, rhr > 1.0
        {
            confidence = .high
        } else if hrvZScore != nil || (sleepScore != nil && bodyBattery != nil) {
            confidence = .moderate
        } else if sleepScore != nil || bodyBattery != nil {
            confidence = .low
        } else {
            confidence = .none
        }

        let explanation = explanations.isEmpty ? "No significant adjustments" : explanations.joined(separator: "; ")

        let output = StateVectorOutput(
            timestamp: Date(),
            hrvModifier: hrvMod,
            sleepModifier: sleepMod,
            bodyBatteryModifier: bbMod,
            rhrModifier: rhrMod,
            netISFModifier: netISF,
            netCRModifier: netCR,
            netBasalModifier: netBasal,
            confidence: confidence,
            hrvZScore: hrvZScore,
            sleepScore: sleepScore,
            bodyBattery: bodyBattery,
            rhrZScore: rhrZScore,
            hoursAwake: hoursAwake,
            explanation: explanation
        )

        latestOutput = output
        lastComputeDate = Date()
        return output
    }

    /// Reset state
    func reset() {
        latestOutput = nil
        lastComputeDate = nil
    }

    // MARK: - Helpers

    private func clampSingle(_ value: Double) -> Double {
        max(-config.singleModifierCap, min(config.singleModifierCap, value))
    }
}
