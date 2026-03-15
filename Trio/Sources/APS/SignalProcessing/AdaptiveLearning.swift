import Foundation

/// Phase 5: Adaptive Learning
///
/// Implements retrospective learning from meal outcomes to personalize
/// absorption speed, protein sensitivity, fat delay, and ISF coefficients.
/// Uses EWMA with adaptive learning rate schedule.
///
/// When the toggle is OFF, the system learns and logs but learned coefficients
/// don't replace configured values. When ON, learned coefficients feed into
/// the MacroMealModel and DailyStateVector.
///
/// Reference: oref improvements §8

final class AdaptiveLearning {
    // MARK: - Configuration

    struct Config {
        /// EWMA alpha schedule (observations 1-10, 11-30, 31+)
        var alphaFastConvergence: Double = 0.25
        var alphaSettling: Double = 0.15
        var alphaStable: Double = 0.07
        /// Observation count thresholds for alpha transitions
        var settlingThreshold: Int = 10
        var stableThreshold: Int = 30
        /// Reset alpha (used after structural change)
        var alphaReset: Double = 0.20
        /// Observations after reset before returning to normal schedule
        var resetObservations: Int = 15
        /// Minimum observations before coefficients are considered valid
        var minimumObservations: Int = 5
        /// Outlier threshold: if prediction error > this multiple of recent variance, flag as outlier
        var outlierThresholdMultiple: Double = 2.5
    }

    // MARK: - Learned Coefficients

    /// All per-user learned coefficients, persisted to disk
    struct LearnedCoefficients: JSON {
        // Carb absorption
        var carbAbsorptionSpeed: CoefficientState = CoefficientState(populationDefault: 0.5)
        // Protein sensitivity (fraction of protein grams that raise BG as carb equivalents)
        var proteinSensitivity: CoefficientState = CoefficientState(populationDefault: 0.20)
        // Fat delay (additional minutes per gram of fat)
        var fatDelay: CoefficientState = CoefficientState(populationDefault: 3.0)
        // Fiber discount factor
        var fiberDiscount: CoefficientState = CoefficientState(populationDefault: 0.5)
        // HRV-to-ISF scaling factor
        var hrvISFScale: CoefficientState = CoefficientState(populationDefault: 0.05)
        // Post-exercise sensitivity peak
        var exercisePeakISF: CoefficientState = CoefficientState(populationDefault: 0.25)

        // Timestamp of last update
        var lastUpdated: Date?
        // Whether a reset was triggered
        var resetTriggeredAt: Date?
    }

    /// State of a single learnable coefficient
    struct CoefficientState: Codable {
        var value: Double
        var populationDefault: Double
        var observationCount: Int = 0
        var recentVariance: Double = 0
        var lastObservedValue: Double?
        var resetCountdown: Int = 0 // Observations remaining in reset mode

        init(populationDefault: Double) {
            value = populationDefault
            self.populationDefault = populationDefault
        }

        var isCalibrated: Bool { observationCount >= 5 }

        /// Current effective alpha based on observation count and reset state
        func currentAlpha(config: Config) -> Double {
            if resetCountdown > 0 {
                return config.alphaReset
            } else if observationCount < config.settlingThreshold {
                return config.alphaFastConvergence
            } else if observationCount < config.stableThreshold {
                return config.alphaSettling
            } else {
                return config.alphaStable
            }
        }
    }

    // MARK: - Meal Retrospective

    /// Result of analyzing a meal's outcome
    struct MealRetrospective: Codable {
        let mealID: UUID
        let timestamp: Date

        // Prediction vs actual
        let predictedPeakBG: Double?
        let actualPeakBG: Double?
        let predictedTimeToReturn: Double?  // minutes to return to target
        let actualTimeToReturn: Double?

        // Error attribution
        let earlyError: Double?    // 0-90 min: carb speed error
        let midError: Double?      // 90-180 min: ISF error
        let lateError: Double?     // 180-360 min: protein/fat error

        // Outlier detection
        let isOutlier: Bool
        let outlierReason: String?

        // Coefficient updates applied
        let carbSpeedUpdate: Double?
        let proteinSensitivityUpdate: Double?
        let fatDelayUpdate: Double?

        // Learning state after update
        let currentAlpha: Double
        let observationCount: Int
    }

    // MARK: - Shadow Output (logged every cycle)

    struct LearningOutput: Codable {
        let timestamp: Date

        // Current learned coefficients
        let carbAbsorptionSpeed: Double
        let carbAbsorptionCalibrated: Bool
        let carbAbsorptionObservations: Int

        let proteinSensitivity: Double
        let proteinSensitivityCalibrated: Bool
        let proteinSensitivityObservations: Int

        let fatDelay: Double
        let fatDelayCalibrated: Bool
        let fatDelayObservations: Int

        let fiberDiscount: Double
        let hrvISFScale: Double
        let exercisePeakISF: Double

        // Overall calibration status
        let overallCalibrationPercent: Int  // 0-100%
        let totalMealsAnalyzed: Int
        let outlierCount: Int

        // Active learning rate
        let currentAlpha: Double
        let resetActive: Bool
    }

    // MARK: - State

    private var config: Config
    private(set) var coefficients: LearnedCoefficients
    private var retrospectives: [MealRetrospective] = []
    private var outlierCount: Int = 0
    private(set) var latestOutput: LearningOutput?

    init(config: Config = Config()) {
        self.config = config
        coefficients = LearnedCoefficients()
    }

    // MARK: - Load/Save

    func loadCoefficients(_ stored: LearnedCoefficients) {
        coefficients = stored
    }

    // MARK: - Meal Retrospective Analysis

    /// Analyze a completed meal's outcome and update coefficients.
    /// Called 4-6 hours after a meal when enough post-meal data exists.
    func analyzeMealOutcome(
        mealID: UUID,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double,
        predictedPeakBG: Double?,
        actualPeakBG: Double?,
        bgErrorEarly: Double?,   // Average BG error 0-90 min
        bgErrorMid: Double?,     // Average BG error 90-180 min
        bgErrorLate: Double?,    // Average BG error 180-360 min
        predictedTimeToReturn: Double?,
        actualTimeToReturn: Double?
    ) -> MealRetrospective {
        // Outlier detection
        let isOutlier: Bool
        let outlierReason: String?

        let totalError = [bgErrorEarly, bgErrorMid, bgErrorLate].compactMap { $0 }.map(abs).reduce(0, +)
        let avgVariance = max(
            coefficients.carbAbsorptionSpeed.recentVariance,
            coefficients.proteinSensitivity.recentVariance,
            1.0
        )

        if totalError > avgVariance * config.outlierThresholdMultiple {
            isOutlier = true
            outlierReason = "Total error \(String(format: "%.0f", totalError)) exceeds \(String(format: "%.1f", config.outlierThresholdMultiple))x variance"
            outlierCount += 1
        } else {
            isOutlier = false
            outlierReason = nil
        }

        var carbUpdate: Double?
        var proteinUpdate: Double?
        var fatUpdate: Double?

        if !isOutlier {
            // Early error → carb absorption speed
            if let early = bgErrorEarly, abs(early) > 5, carbs > 10 {
                // Positive early error = BG higher than predicted = absorbing faster
                let observedSpeedAdjustment = early > 0
                    ? coefficients.carbAbsorptionSpeed.value * 1.1
                    : coefficients.carbAbsorptionSpeed.value * 0.9
                updateCoefficient(&coefficients.carbAbsorptionSpeed, observed: observedSpeedAdjustment)
                carbUpdate = coefficients.carbAbsorptionSpeed.value
            }

            // Late error → protein sensitivity
            if let late = bgErrorLate, abs(late) > 10, protein > 15 {
                // Positive late error = more protein impact than modeled
                let observedProteinSens = late > 0
                    ? coefficients.proteinSensitivity.value * 1.1
                    : coefficients.proteinSensitivity.value * 0.9
                updateCoefficient(&coefficients.proteinSensitivity, observed: observedProteinSens)
                proteinUpdate = coefficients.proteinSensitivity.value
            }

            // Mid-to-late timing → fat delay
            if let mid = bgErrorMid, let late = bgErrorLate, fat > 10 {
                // If mid is low but late is high, fat delay is underestimated
                if mid < -5 && late > 10 {
                    let adjustedDelay = coefficients.fatDelay.value * 1.15
                    updateCoefficient(&coefficients.fatDelay, observed: adjustedDelay)
                    fatUpdate = coefficients.fatDelay.value
                } else if mid > 10 && late < -5 {
                    let adjustedDelay = coefficients.fatDelay.value * 0.85
                    updateCoefficient(&coefficients.fatDelay, observed: adjustedDelay)
                    fatUpdate = coefficients.fatDelay.value
                }
            }
        }

        coefficients.lastUpdated = Date()

        let alpha = coefficients.carbAbsorptionSpeed.currentAlpha(config: config)
        let obsCount = coefficients.carbAbsorptionSpeed.observationCount

        let retro = MealRetrospective(
            mealID: mealID,
            timestamp: Date(),
            predictedPeakBG: predictedPeakBG,
            actualPeakBG: actualPeakBG,
            predictedTimeToReturn: predictedTimeToReturn,
            actualTimeToReturn: actualTimeToReturn,
            earlyError: bgErrorEarly,
            midError: bgErrorMid,
            lateError: bgErrorLate,
            isOutlier: isOutlier,
            outlierReason: outlierReason,
            carbSpeedUpdate: carbUpdate,
            proteinSensitivityUpdate: proteinUpdate,
            fatDelayUpdate: fatUpdate,
            currentAlpha: alpha,
            observationCount: obsCount
        )

        retrospectives.append(retro)
        // Keep last 90 days of retrospectives
        if retrospectives.count > 1000 {
            retrospectives = Array(retrospectives.suffix(500))
        }

        return retro
    }

    // MARK: - Trigger Coefficient Reset

    /// Partially reset learning rates when a structural change is detected.
    func triggerReset(reason: String) {
        let resetCount = config.resetObservations
        coefficients.carbAbsorptionSpeed.resetCountdown = resetCount
        coefficients.proteinSensitivity.resetCountdown = resetCount
        coefficients.fatDelay.resetCountdown = resetCount
        coefficients.hrvISFScale.resetCountdown = resetCount
        coefficients.exercisePeakISF.resetCountdown = resetCount
        coefficients.resetTriggeredAt = Date()
    }

    // MARK: - Generate Shadow Output

    /// Generate the current learning state output for logging/export.
    func generateOutput() -> LearningOutput {
        let totalObs = coefficients.carbAbsorptionSpeed.observationCount +
            coefficients.proteinSensitivity.observationCount +
            coefficients.fatDelay.observationCount

        // Calibration: what percentage of coefficients are calibrated
        let calibratedCount = [
            coefficients.carbAbsorptionSpeed,
            coefficients.proteinSensitivity,
            coefficients.fatDelay,
            coefficients.fiberDiscount,
            coefficients.hrvISFScale,
            coefficients.exercisePeakISF,
        ].filter(\.isCalibrated).count

        let calibrationPercent = Int(Double(calibratedCount) / 6.0 * 100)
        let resetActive = coefficients.carbAbsorptionSpeed.resetCountdown > 0

        let output = LearningOutput(
            timestamp: Date(),
            carbAbsorptionSpeed: coefficients.carbAbsorptionSpeed.value,
            carbAbsorptionCalibrated: coefficients.carbAbsorptionSpeed.isCalibrated,
            carbAbsorptionObservations: coefficients.carbAbsorptionSpeed.observationCount,
            proteinSensitivity: coefficients.proteinSensitivity.value,
            proteinSensitivityCalibrated: coefficients.proteinSensitivity.isCalibrated,
            proteinSensitivityObservations: coefficients.proteinSensitivity.observationCount,
            fatDelay: coefficients.fatDelay.value,
            fatDelayCalibrated: coefficients.fatDelay.isCalibrated,
            fatDelayObservations: coefficients.fatDelay.observationCount,
            fiberDiscount: coefficients.fiberDiscount.value,
            hrvISFScale: coefficients.hrvISFScale.value,
            exercisePeakISF: coefficients.exercisePeakISF.value,
            overallCalibrationPercent: calibrationPercent,
            totalMealsAnalyzed: retrospectives.count,
            outlierCount: outlierCount,
            currentAlpha: coefficients.carbAbsorptionSpeed.currentAlpha(config: config),
            resetActive: resetActive
        )

        latestOutput = output
        return output
    }

    func reset() {
        coefficients = LearnedCoefficients()
        retrospectives = []
        outlierCount = 0
        latestOutput = nil
    }

    // MARK: - Private EWMA Update

    private func updateCoefficient(_ state: inout CoefficientState, observed: Double) {
        let alpha = state.currentAlpha(config: config)
        let oldValue = state.value
        state.value = alpha * observed + (1 - alpha) * oldValue
        state.observationCount += 1
        state.lastObservedValue = observed

        // Update running variance estimate
        let error = observed - oldValue
        state.recentVariance = alpha * (error * error) + (1 - alpha) * state.recentVariance

        // Decrement reset countdown if active
        if state.resetCountdown > 0 {
            state.resetCountdown -= 1
        }
    }
}
