import Combine
import Foundation
import Swinject

/// Protocol for the oref signal processing pipeline (Phases 1–5).
///
/// Orchestrates the adaptive Kalman filter, BG derivative calculation,
/// residual computation, Garmin Z-score normalization, macro-aware meal model,
/// daily state vector, exercise sensitivity model, and adaptive learning.
///
/// Each phase runs in shadow mode (compute + log) by default.
/// Phase toggles gate whether computed values feed into oref decisions.
protocol OrefSignalPipeline {
    /// Process a new CGM glucose reading through the full signal pipeline.
    /// Called every ~5 minutes when a new CGM value arrives.
    @discardableResult
    func processGlucose(
        rawBG: Double,
        at timestamp: Date,
        activity: Double?,
        isf: Double?,
        cr: Double?
    ) -> OrefSignalOutput

    /// Process daily Garmin data (called after overnight sync).
    func processGarminData(_ snapshot: GarminContextSnapshot)

    /// Register a meal for the macro-aware model (Phase 2).
    func registerMeal(id: UUID, at timestamp: Date, carbs: Double, fat: Double, protein: Double, fiber: Double)

    /// Persist signal logs to disk.
    func save()

    /// Reset all signal state (e.g. on sensor change).
    func reset()

    /// Latest signal output, if available.
    var latestOutput: OrefSignalOutput? { get }

    /// Publisher that emits when a new signal output is available.
    var outputPublisher: AnyPublisher<OrefSignalOutput, Never> { get }

    /// Access to the signal store for export purposes.
    var store: SignalStore { get }

    /// Access to Phase 2-5 components for export/UI.
    var macroMealModel: MacroMealModel { get }
    var dailyStateVector: DailyStateVector { get }
    var exerciseSensitivityModel: ExerciseSensitivityModel { get }
    var adaptiveLearning: AdaptiveLearning { get }
}

/// Combined output from the signal pipeline for a single CGM reading.
struct OrefSignalOutput {
    let timestamp: Date

    // Phase 1: Kalman filter
    let smoothedBG: Double
    let velocity: Double
    let acceleration: Double
    let jerk: Double?
    let bgUncertainty: Double

    // Phase 1: Residual
    let residual: Double?
    let residualRate: Double?
    let estimatedCarbAbsorptionRate: Double?

    // Phase 1: Meal detection
    let mealDetectionConfidence: BGSignalProcessor.MealDetectionConfidence

    // Raw for comparison
    let rawBG: Double

    // Phase 2: Macro-aware meal model (shadow mode data)
    let mealModelOutput: MacroMealModel.MealModelOutput?

    // Phase 3: Daily state vector (shadow mode data)
    let stateVectorOutput: DailyStateVector.StateVectorOutput?

    // Phase 4: Exercise sensitivity (shadow mode data)
    let exerciseOutput: ExerciseSensitivityModel.ExerciseOutput?

    // Phase 5: Adaptive learning (shadow mode data)
    let learningOutput: AdaptiveLearning.LearningOutput?
}

// MARK: - Implementation

final class BaseOrefSignalPipeline: OrefSignalPipeline, Injectable {
    @Injected() private var storage: FileStorage!

    // Phase 1
    private let signalProcessor: BGSignalProcessor
    private let residualCalculator: BGResidualCalculator
    private let zScoreNormalizer: GarminZScoreNormalizer
    private var _signalStore: SignalStore!

    // Phase 2–5
    private let _macroMealModel: MacroMealModel
    private let _dailyStateVector: DailyStateVector
    private let _exerciseSensitivityModel: ExerciseSensitivityModel
    private let _adaptiveLearning: AdaptiveLearning

    // Last Garmin snapshot for Phase 3/4 processing
    private var lastGarminSnapshot: GarminContextSnapshot?
    private var lastZScores: GarminZScoreNormalizer.ZScoreSnapshot?

    var store: SignalStore { _signalStore }
    var macroMealModel: MacroMealModel { _macroMealModel }
    var dailyStateVector: DailyStateVector { _dailyStateVector }
    var exerciseSensitivityModel: ExerciseSensitivityModel { _exerciseSensitivityModel }
    var adaptiveLearning: AdaptiveLearning { _adaptiveLearning }

    private let outputSubject = PassthroughSubject<OrefSignalOutput, Never>()

    private(set) var latestOutput: OrefSignalOutput?

    var outputPublisher: AnyPublisher<OrefSignalOutput, Never> {
        outputSubject.eraseToAnyPublisher()
    }

    init(resolver: Resolver) {
        signalProcessor = BGSignalProcessor()
        residualCalculator = BGResidualCalculator()
        zScoreNormalizer = GarminZScoreNormalizer()
        _macroMealModel = MacroMealModel()
        _dailyStateVector = DailyStateVector()
        _exerciseSensitivityModel = ExerciseSensitivityModel()
        _adaptiveLearning = AdaptiveLearning()
        injectServices(resolver)
        _signalStore = SignalStore(storage: storage)
        loadZScoreBaseline()
        loadLearnedCoefficients()
    }

    // MARK: - Meal Registration (Phase 2)

    func registerMeal(id: UUID, at timestamp: Date, carbs: Double, fat: Double, protein: Double, fiber: Double) {
        _macroMealModel.registerMeal(id: id, at: timestamp, carbs: carbs, fat: fat, protein: protein, fiber: fiber)
        debug(
            .openAPS,
            "OrefSignal: Meal registered — \(String(format: "%.0f", carbs))C/\(String(format: "%.0f", fat))F/" +
            "\(String(format: "%.0f", protein))P/\(String(format: "%.0f", fiber))fiber"
        )
    }

    // MARK: - Process CGM Reading

    func processGlucose(
        rawBG: Double,
        at timestamp: Date,
        activity: Double?,
        isf: Double?,
        cr: Double?
    ) -> OrefSignalOutput {
        // Step 1: Run through Kalman filter + meal detection
        let signalOutput = signalProcessor.processReading(glucose: rawBG, at: timestamp)

        // Step 2: Calculate residual if insulin activity data is available
        var residualEntry: BGResidualCalculator.ResidualEntry?
        if let activity = activity, let isf = isf {
            residualEntry = residualCalculator.update(
                filteredBG: signalOutput.filter.bg,
                activity: activity,
                isf: isf,
                cr: cr,
                timestamp: timestamp
            )
        }

        // Step 3: Phase 2 — Macro meal model cycle (always compute, toggle gates oref feed)
        let mealOutput = _macroMealModel.processCycle(
            at: timestamp,
            observedCarbAbsorptionRate: residualEntry?.estimatedCarbAbsorptionRate,
            currentISF: isf ?? 50.0,
            currentCR: cr,
            orefCOB: nil
        )

        // Step 4: Phase 5 — Generate learning output snapshot
        let learningOutput = _adaptiveLearning.generateOutput()

        // Step 5: Build combined output
        let output = OrefSignalOutput(
            timestamp: timestamp,
            smoothedBG: signalOutput.filter.bg,
            velocity: signalOutput.filter.velocity,
            acceleration: signalOutput.filter.acceleration,
            jerk: signalOutput.filter.jerk,
            bgUncertainty: signalOutput.filter.bgUncertainty,
            residual: residualEntry?.residual,
            residualRate: residualEntry?.residualRate,
            estimatedCarbAbsorptionRate: residualEntry?.estimatedCarbAbsorptionRate,
            mealDetectionConfidence: signalOutput.mealSignal.confidence,
            rawBG: rawBG,
            mealModelOutput: mealOutput.absorptionPhase != .none ? mealOutput : nil,
            stateVectorOutput: _dailyStateVector.latestOutput,
            exerciseOutput: _exerciseSensitivityModel.latestOutput,
            learningOutput: learningOutput
        )

        // Step 6: Log to signal store (includes Phase 2-5 shadow data)
        let logEntry = SignalStore.SignalEntry(
            timestamp: timestamp,
            smoothedBG: signalOutput.filter.bg,
            velocity: signalOutput.filter.velocity,
            acceleration: signalOutput.filter.acceleration,
            jerk: signalOutput.filter.jerk,
            bgUncertainty: signalOutput.filter.bgUncertainty,
            velocityUncertainty: signalOutput.filter.velocityUncertainty,
            accelerationUncertainty: signalOutput.filter.accelerationUncertainty,
            rawBG: rawBG,
            residual: residualEntry?.residual,
            residualRate: residualEntry?.residualRate,
            estimatedCarbAbsorptionRate: residualEntry?.estimatedCarbAbsorptionRate,
            mealDetectionConfidence: signalOutput.mealSignal.confidence.rawValue,
            accelerationSignalActive: signalOutput.mealSignal.accelerationSignal,
            jerkConfirmationActive: signalOutput.mealSignal.jerkConfirmation,
            velocitySignalActive: signalOutput.mealSignal.velocitySignal,
            // Phase 2 shadow data
            bayesianCOB: mealOutput.bayesianCOB,
            fatProteinTailCOB: mealOutput.fatProteinTailCOB,
            absorptionPhase: mealOutput.absorptionPhase.rawValue,
            predictedAbsorptionRate: mealOutput.predictedAbsorptionRate,
            estimateConfidence: mealOutput.estimateConfidence.rawValue,
            // Phase 3 shadow data
            dailyISFModifier: _dailyStateVector.latestOutput?.netISFModifier,
            dailyCRModifier: _dailyStateVector.latestOutput?.netCRModifier,
            stateVectorConfidence: _dailyStateVector.latestOutput?.confidence.rawValue,
            // Phase 4 shadow data
            exerciseISFModifier: _exerciseSensitivityModel.latestOutput?.netISFModifier,
            exerciseCRModifier: _exerciseSensitivityModel.latestOutput?.crModifier,
            exerciseWindowActive: _exerciseSensitivityModel.latestOutput?.exerciseSensitivityWindowActive ?? false,
            // Phase 5 shadow data
            learnedCarbSpeed: learningOutput.carbAbsorptionSpeed,
            learnedProteinSens: learningOutput.proteinSensitivity,
            learnedFatDelay: learningOutput.fatDelay,
            calibrationPercent: learningOutput.overallCalibrationPercent
        )
        _signalStore.logSignal(logEntry)

        latestOutput = output
        outputSubject.send(output)

        debug(
            .openAPS,
            "OrefSignal: BG=\(String(format: "%.0f", rawBG))→\(String(format: "%.1f", output.smoothedBG)) " +
            "v=\(String(format: "%.2f", output.velocity)) " +
            "a=\(String(format: "%.3f", output.acceleration)) " +
            "j=\(output.jerk.map { String(format: "%.4f", $0) } ?? "nil") " +
            "res=\(output.residual.map { String(format: "%.1f", $0) } ?? "nil") " +
            "meal=\(output.mealDetectionConfidence.rawValue) " +
            "bCOB=\(mealOutput.bayesianCOB.map { String(format: "%.0f", $0) } ?? "-") " +
            "dISF=\(_dailyStateVector.latestOutput.map { String(format: "%+.0f%%", $0.netISFModifier * 100) } ?? "-") " +
            "xISF=\(_exerciseSensitivityModel.latestOutput.map { String(format: "%+.0f%%", $0.netISFModifier * 100) } ?? "-")"
        )

        return output
    }

    // MARK: - Process Garmin Data

    func processGarminData(_ snapshot: GarminContextSnapshot) {
        lastGarminSnapshot = snapshot

        // Phase 1: Z-score normalization
        let metric = zScoreNormalizer.metricFromSnapshot(snapshot)
        let zScores = zScoreNormalizer.addDailyMetric(metric)
        lastZScores = zScores

        let logEntry = SignalStore.DailyZScoreEntry(
            date: zScores.date,
            hrvZScore: zScores.hrvZScore,
            restingHRZScore: zScores.restingHRZScore,
            sleepScoreZScore: zScores.sleepScoreZScore,
            sleepDurationZScore: zScores.sleepDurationZScore,
            deepSleepZScore: zScores.deepSleepZScore,
            bodyBatteryZScore: zScores.bodyBatteryZScore,
            stressConfidence: zScores.stressSignalConfidence.rawValue,
            baselineSize: zScores.baselineSize,
            hrvRMSSD: metric.hrvRMSSD,
            restingHR: metric.restingHR,
            sleepScore: metric.sleepScore,
            sleepDurationMinutes: metric.sleepDurationMinutes
        )
        _signalStore.logDailyZScore(logEntry)

        // Phase 3: Compute daily state vector from Z-scores
        let hoursAwake = estimateHoursAwake(from: snapshot)
        let stateVector = _dailyStateVector.compute(
            hrvZScore: zScores.hrvZScore,
            rhrZScore: zScores.restingHRZScore,
            sleepScore: metric.sleepScore,
            sleepDurationMinutes: metric.sleepDurationMinutes,
            bodyBattery: snapshot.currentBodyBattery.map(Double.init),
            stressConfidence: zScores.stressSignalConfidence.rawValue,
            hoursAwake: hoursAwake
        )

        // Phase 4: Compute exercise sensitivity from Garmin activity data
        let exerciseOutput = _exerciseSensitivityModel.compute(
            yesterdayActiveCalories: snapshot.yesterdayActiveKilocalories,
            yesterdayVigorousMinutes: snapshot.yesterdayVigorousIntensityDurationInSeconds.map { $0 / 60 },
            yesterdayModerateMinutes: snapshot.yesterdayModerateIntensityDurationInSeconds.map { $0 / 60 },
            todayActiveCalories: snapshot.activeKilocalories,
            todayVigorousMinutes: snapshot.vigorousIntensityDurationInSeconds.map { $0 / 60 },
            todayModerateMinutes: snapshot.moderateIntensityDurationInSeconds.map { $0 / 60 }
        )

        // Persist baselines
        saveZScoreBaseline()

        debug(
            .openAPS,
            "OrefSignal Z-Scores: HRV=\(zScores.hrvZScore.map { String(format: "%.2f", $0) } ?? "nil") " +
            "RHR=\(zScores.restingHRZScore.map { String(format: "%.2f", $0) } ?? "nil") " +
            "sleep=\(zScores.sleepScoreZScore.map { String(format: "%.2f", $0) } ?? "nil") " +
            "stress=\(zScores.stressSignalConfidence.rawValue) " +
            "baseline=\(zScores.baselineSize)d " +
            "stateISF=\(String(format: "%+.0f%%", stateVector.netISFModifier * 100)) " +
            "exercISF=\(String(format: "%+.0f%%", exerciseOutput.netISFModifier * 100))"
        )
    }

    // MARK: - Lifecycle

    func save() {
        _signalStore.save()
        saveZScoreBaseline()
        saveLearnedCoefficients()
    }

    func reset() {
        signalProcessor.reset()
        residualCalculator.reset()
        _macroMealModel.reset()
        latestOutput = nil
    }

    // MARK: - Persistence

    private static let zScoreBaselineFile = "oref_zscore_baseline.json"
    private static let learnedCoefficientsFile = "oref_learned_coefficients.json"

    private func saveZScoreBaseline() {
        storage.save(zScoreNormalizer.baseline, as: Self.zScoreBaselineFile)
    }

    private func loadZScoreBaseline() {
        if let baseline: [GarminZScoreNormalizer.DailyMetric] = storage.retrieve(
            Self.zScoreBaselineFile,
            as: [GarminZScoreNormalizer.DailyMetric].self
        ) {
            zScoreNormalizer.loadBaseline(baseline)
        }
    }

    private func saveLearnedCoefficients() {
        storage.save(_adaptiveLearning.coefficients, as: Self.learnedCoefficientsFile)
    }

    private func loadLearnedCoefficients() {
        if let coefficients: AdaptiveLearning.LearnedCoefficients = storage.retrieve(
            Self.learnedCoefficientsFile,
            as: AdaptiveLearning.LearnedCoefficients.self
        ) {
            _adaptiveLearning.loadCoefficients(coefficients)
        }
    }

    // MARK: - Helpers

    private func estimateHoursAwake(from snapshot: GarminContextSnapshot) -> Double? {
        // Estimate hours since wake based on current time
        // A more accurate version would use Garmin sleep end time
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let currentHour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        // Assume wake at 7am if no sleep data
        let estimatedWake = 7.0
        return max(0, currentHour - estimatedWake)
    }
}
