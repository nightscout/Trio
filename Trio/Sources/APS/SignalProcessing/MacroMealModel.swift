import Foundation

/// Phase 2: Macro-Aware Meal Model
///
/// Replaces oref's linear carb absorption with a composite macronutrient model.
/// Constructs predicted BG impact curves from carb/fat/protein/fiber data,
/// implements Bayesian absorption estimation, and tracks fat-protein tail predictions.
///
/// When the toggle is OFF, this runs in shadow mode — computing what it would do
/// and logging it, but not affecting oref's COB or dosing decisions.
///
/// Reference: oref improvements §5, §9.2

final class MacroMealModel {
    // MARK: - Configuration

    struct Config {
        /// Fiber discount factor: effectiveCarbs = carbs - (fiber * fiberDiscount)
        var fiberDiscount: Double = 0.5
        /// Default carb absorption speed (g/min) before personalization
        var defaultCarbAbsorptionRate: Double = 0.5
        /// Protein-to-BG conversion factor (mg/dL per gram, population default)
        var proteinSensitivity: Double = 0.5
        /// Fat delay factor: how many additional minutes per gram of fat
        var fatDelayPerGram: Double = 3.0
        /// Protein onset delay (minutes)
        var proteinOnsetMinutes: Double = 120.0
        /// Protein peak (minutes)
        var proteinPeakMinutes: Double = 210.0
        /// Protein duration (minutes)
        var proteinDurationMinutes: Double = 360.0
        /// Fat onset delay (minutes)
        var fatOnsetMinutes: Double = 180.0
        /// Fat peak (minutes)
        var fatPeakMinutes: Double = 300.0
        /// Fat duration (minutes)
        var fatDurationMinutes: Double = 480.0
        /// EMA alpha for Bayesian absorption rate tracking
        var absorptionEMAAlpha: Double = 0.3
        /// Minimum ISF to prevent division by zero
        var minISF: Double = 5.0
    }

    // MARK: - Meal State

    /// Represents an active meal being tracked by the model
    struct ActiveMeal {
        let mealID: UUID
        let timestamp: Date
        let carbs: Double
        let fat: Double
        let protein: Double
        let fiber: Double
        let effectiveCarbs: Double
        let predictedCarbPeakMinutes: Double
        let predictedSecondaryOnsetMinutes: Double
        let predictedSecondaryPeakMinutes: Double
        let predictedTotalDurationMinutes: Double
    }

    /// Shadow-mode output: what the model computes each cycle
    struct MealModelOutput {
        let timestamp: Date

        // Active meal context
        let activeMealID: UUID?
        let minutesSinceMeal: Double?

        // Effective carbs after fiber adjustment
        let effectiveCarbs: Double?

        // Bayesian COB estimate (what we'd tell oref)
        let bayesianCOB: Double?
        /// How much of the difference is from the fat-protein tail
        let fatProteinTailCOB: Double?

        // Predicted vs actual absorption
        let predictedAbsorptionRate: Double?  // g/min from macro curve
        let observedAbsorptionRate: Double?   // g/min from residual

        // Absorption phase classification
        let absorptionPhase: AbsorptionPhase

        // Composite predicted BG impact remaining (mg/dL)
        let predictedRemainingImpact: Double?

        // Confidence in the estimate
        let estimateConfidence: EstimateConfidence
    }

    enum AbsorptionPhase: String, Codable {
        case none = "none"
        case primaryCarbs = "primary_carbs"       // 0–2h: fast carb absorption
        case transitionPhase = "transition"        // 1.5–3h: carbs winding down, protein starting
        case fatProteinTail = "fat_protein_tail"   // 2–8h: secondary rise from protein/fat
        case completed = "completed"
    }

    enum EstimateConfidence: String, Codable {
        case high = "high"       // Full Cronometer macros available
        case medium = "medium"   // Carbs only (no fat/protein)
        case low = "low"         // UAM / no meal data
        case none = "none"       // No active meal
    }

    // MARK: - State

    private var config: Config
    private var activeMeal: ActiveMeal?
    private var cumulativeAbsorbed: Double = 0
    private var smoothedObservedRate: Double = 0
    private(set) var latestOutput: MealModelOutput?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Meal Registration

    /// Register a new meal from Cronometer macros or manual entry.
    func registerMeal(
        id: UUID,
        at timestamp: Date,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double
    ) {
        let effectiveCarbs = max(0, carbs - (fiber * config.fiberDiscount))

        // Estimate carb peak delay based on fat content (fat slows gastric emptying)
        let fatDelay = fat * config.fatDelayPerGram
        let carbPeakMinutes = 45.0 + min(fatDelay, 60.0) // 45min base + up to 60min fat delay

        // Protein/fat tail timing
        let secondaryOnset = config.proteinOnsetMinutes
        let secondaryPeak: Double
        if fat > 15 && protein > 20 {
            secondaryPeak = config.fatPeakMinutes // Heavy fat+protein: later peak
        } else if protein > 20 {
            secondaryPeak = config.proteinPeakMinutes
        } else {
            secondaryPeak = config.proteinOnsetMinutes + 60
        }

        // Total duration based on fat+protein content
        let totalDuration: Double
        if fat + protein > 60 {
            totalDuration = config.fatDurationMinutes // 8h for heavy meals
        } else if fat + protein > 30 {
            totalDuration = config.proteinDurationMinutes // 6h
        } else {
            totalDuration = 180 // 3h for light meals
        }

        activeMeal = ActiveMeal(
            mealID: id,
            timestamp: timestamp,
            carbs: carbs,
            fat: fat,
            protein: protein,
            fiber: fiber,
            effectiveCarbs: effectiveCarbs,
            predictedCarbPeakMinutes: carbPeakMinutes,
            predictedSecondaryOnsetMinutes: secondaryOnset,
            predictedSecondaryPeakMinutes: secondaryPeak,
            predictedTotalDurationMinutes: totalDuration
        )
        cumulativeAbsorbed = 0
        smoothedObservedRate = 0
    }

    // MARK: - Process Cycle

    /// Called every ~5 minutes. Uses residual data to update absorption estimate.
    func processCycle(
        at timestamp: Date,
        observedCarbAbsorptionRate: Double?,
        currentISF: Double,
        currentCR: Double?,
        orefCOB: Double?
    ) -> MealModelOutput {
        guard let meal = activeMeal else {
            let output = MealModelOutput(
                timestamp: timestamp,
                activeMealID: nil,
                minutesSinceMeal: nil,
                effectiveCarbs: nil,
                bayesianCOB: nil,
                fatProteinTailCOB: nil,
                predictedAbsorptionRate: nil,
                observedAbsorptionRate: nil,
                absorptionPhase: .none,
                predictedRemainingImpact: nil,
                estimateConfidence: .none
            )
            latestOutput = output
            return output
        }

        let minutesSinceMeal = timestamp.timeIntervalSince(meal.timestamp) / 60.0

        // Check if meal is completed
        if minutesSinceMeal > meal.predictedTotalDurationMinutes {
            let output = MealModelOutput(
                timestamp: timestamp,
                activeMealID: meal.mealID,
                minutesSinceMeal: minutesSinceMeal,
                effectiveCarbs: meal.effectiveCarbs,
                bayesianCOB: 0,
                fatProteinTailCOB: 0,
                predictedAbsorptionRate: 0,
                observedAbsorptionRate: observedCarbAbsorptionRate,
                absorptionPhase: .completed,
                predictedRemainingImpact: 0,
                estimateConfidence: estimateConfidence(for: meal)
            )
            latestOutput = output
            return output
        }

        // Predicted absorption rate from macro curve
        let predictedRate = predictedAbsorptionRate(at: minutesSinceMeal, meal: meal)

        // Update observed rate with EMA
        if let observed = observedCarbAbsorptionRate, observed > 0 {
            smoothedObservedRate = config.absorptionEMAAlpha * observed +
                (1 - config.absorptionEMAAlpha) * smoothedObservedRate
        }

        // Bayesian blend: weight observed more as we get more data
        let observationWeight = min(minutesSinceMeal / 30.0, 0.7) // Ramp up to 70% over 30 min
        let blendedRate: Double
        if smoothedObservedRate > 0 {
            blendedRate = observationWeight * smoothedObservedRate + (1 - observationWeight) * predictedRate
        } else {
            blendedRate = predictedRate
        }

        // Update cumulative absorbed (5-min interval)
        cumulativeAbsorbed += blendedRate * 5.0

        // Compute remaining COB
        let totalEquivalentCarbs = meal.effectiveCarbs + fatProteinEquivalentCarbs(meal: meal)
        let bayesianCOB = max(0, totalEquivalentCarbs - cumulativeAbsorbed)

        // Fat-protein tail COB specifically
        let primaryCarbsRemaining = max(0, meal.effectiveCarbs - cumulativeAbsorbed)
        let tailCOB = max(0, bayesianCOB - primaryCarbsRemaining)

        // Remaining BG impact
        let isf = max(config.minISF, currentISF)
        let cr = currentCR ?? 10.0
        let remainingImpact = bayesianCOB / cr * isf

        // Classify absorption phase
        let phase = classifyPhase(minutesSinceMeal: minutesSinceMeal, meal: meal)

        let output = MealModelOutput(
            timestamp: timestamp,
            activeMealID: meal.mealID,
            minutesSinceMeal: minutesSinceMeal,
            effectiveCarbs: meal.effectiveCarbs,
            bayesianCOB: bayesianCOB,
            fatProteinTailCOB: tailCOB,
            predictedAbsorptionRate: predictedRate,
            observedAbsorptionRate: smoothedObservedRate > 0 ? smoothedObservedRate : nil,
            absorptionPhase: phase,
            predictedRemainingImpact: remainingImpact,
            estimateConfidence: estimateConfidence(for: meal)
        )
        latestOutput = output
        return output
    }

    // MARK: - Reset

    func reset() {
        activeMeal = nil
        cumulativeAbsorbed = 0
        smoothedObservedRate = 0
        latestOutput = nil
    }

    // MARK: - Private Helpers

    /// Predicted carb absorption rate at a given time from the composite macro curve.
    private func predictedAbsorptionRate(at minutes: Double, meal: ActiveMeal) -> Double {
        // Primary carb curve: trapezoidal with fat-adjusted peak
        let carbRate = carbAbsorptionCurve(
            at: minutes,
            totalCarbs: meal.effectiveCarbs,
            peakMinutes: meal.predictedCarbPeakMinutes
        )

        // Protein contribution: delayed bell curve
        let proteinRate = secondaryAbsorptionCurve(
            at: minutes,
            totalGrams: meal.protein,
            sensitivityFactor: config.proteinSensitivity * 0.4, // 40% of protein converts
            onsetMinutes: config.proteinOnsetMinutes,
            peakMinutes: meal.predictedSecondaryPeakMinutes,
            durationMinutes: config.proteinDurationMinutes
        )

        // Fat contribution: even more delayed
        let fatRate = secondaryAbsorptionCurve(
            at: minutes,
            totalGrams: meal.fat,
            sensitivityFactor: 0.1, // ~10% of fat converts to glucose equivalent
            onsetMinutes: config.fatOnsetMinutes,
            peakMinutes: meal.predictedSecondaryPeakMinutes + 60,
            durationMinutes: config.fatDurationMinutes
        )

        return carbRate + proteinRate + fatRate
    }

    /// Trapezoidal carb absorption curve
    private func carbAbsorptionCurve(at minutes: Double, totalCarbs: Double, peakMinutes: Double) -> Double {
        guard minutes >= 0, totalCarbs > 0 else { return 0 }

        let duration = peakMinutes * 2.5 // Total absorption window
        if minutes > duration { return 0 }

        // Trapezoidal: ramp up to peak, plateau, ramp down
        let rampUp = peakMinutes * 0.5
        let plateau = peakMinutes
        let rampDown = duration

        let rate: Double
        if minutes < rampUp {
            rate = (minutes / rampUp) * config.defaultCarbAbsorptionRate
        } else if minutes < plateau {
            rate = config.defaultCarbAbsorptionRate
        } else {
            let decay = (minutes - plateau) / (rampDown - plateau)
            rate = config.defaultCarbAbsorptionRate * max(0, 1 - decay)
        }

        return rate
    }

    /// Bell-curve absorption for protein/fat secondary effects
    private func secondaryAbsorptionCurve(
        at minutes: Double,
        totalGrams: Double,
        sensitivityFactor: Double,
        onsetMinutes: Double,
        peakMinutes: Double,
        durationMinutes: Double
    ) -> Double {
        guard minutes >= onsetMinutes, totalGrams > 0 else { return 0 }
        if minutes > durationMinutes { return 0 }

        let effectiveGrams = totalGrams * sensitivityFactor
        let sigma = (durationMinutes - onsetMinutes) / 4.0
        let center = peakMinutes
        let exponent = -pow(minutes - center, 2) / (2 * sigma * sigma)
        let gaussianValue = exp(exponent)

        // Scale to deliver effectiveGrams over the duration
        // Peak rate ≈ effectiveGrams / (sigma * sqrt(2π))
        let peakRate = effectiveGrams / (sigma * sqrt(2 * .pi))
        return peakRate * gaussianValue
    }

    /// Fat-protein equivalent carbs (used for total COB tracking)
    private func fatProteinEquivalentCarbs(meal: ActiveMeal) -> Double {
        // Warsaw/Krakow method: FPU = (fat*9 + protein*4) / 10, as gram equivalents
        let fpu = (meal.fat * 9 + meal.protein * 4) / 10.0
        return fpu * 0.5 // Conservative: 50% of FPU actually raises BG
    }

    private func classifyPhase(minutesSinceMeal: Double, meal: ActiveMeal) -> AbsorptionPhase {
        if minutesSinceMeal < meal.predictedSecondaryOnsetMinutes * 0.8 {
            return .primaryCarbs
        } else if minutesSinceMeal < meal.predictedSecondaryOnsetMinutes {
            return .transitionPhase
        } else {
            return .fatProteinTail
        }
    }

    private func estimateConfidence(for meal: ActiveMeal) -> EstimateConfidence {
        if meal.fat > 0 && meal.protein > 0 {
            return .high // Full Cronometer macros
        } else if meal.carbs > 0 {
            return .medium // Carbs only
        } else {
            return .low
        }
    }
}
