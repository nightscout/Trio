import Combine
import Foundation
import Swinject

/// Protocol for the Phase 1 signal processing pipeline.
///
/// Orchestrates the adaptive Kalman filter, BG derivative calculation,
/// residual computation, Garmin Z-score normalization, and signal logging.
/// In Phase 1, this pipeline computes and logs data without affecting dosing.
protocol OrefSignalPipeline {
    /// Process a new CGM glucose reading through the full signal pipeline.
    /// Called every ~5 minutes when a new CGM value arrives.
    @discardableResult
    func processGlucose(
        rawBG: Double,
        at timestamp: Date,
        iob: Double?,
        isf: Double?,
        cr: Double?
    ) -> OrefSignalOutput

    /// Process daily Garmin data (called after overnight sync).
    func processGarminData(_ snapshot: GarminContextSnapshot)

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
}

/// Combined output from the signal pipeline for a single CGM reading.
struct OrefSignalOutput {
    let timestamp: Date

    // Kalman filter
    let smoothedBG: Double
    let velocity: Double
    let acceleration: Double
    let jerk: Double?
    let bgUncertainty: Double

    // Residual
    let residual: Double?
    let residualRate: Double?
    let estimatedCarbAbsorptionRate: Double?

    // Meal detection
    let mealDetectionConfidence: BGSignalProcessor.MealDetectionConfidence

    // Raw for comparison
    let rawBG: Double
}

// MARK: - Implementation

final class BaseOrefSignalPipeline: OrefSignalPipeline, Injectable {
    @Injected() private var storage: FileStorage!

    private let signalProcessor: BGSignalProcessor
    private let residualCalculator: BGResidualCalculator
    private let zScoreNormalizer: GarminZScoreNormalizer
    private var _signalStore: SignalStore!

    var store: SignalStore { _signalStore }

    private let outputSubject = PassthroughSubject<OrefSignalOutput, Never>()

    private(set) var latestOutput: OrefSignalOutput?

    var outputPublisher: AnyPublisher<OrefSignalOutput, Never> {
        outputSubject.eraseToAnyPublisher()
    }

    init(resolver: Resolver) {
        signalProcessor = BGSignalProcessor()
        residualCalculator = BGResidualCalculator()
        zScoreNormalizer = GarminZScoreNormalizer()
        injectServices(resolver)
        _signalStore = SignalStore(storage: storage)
        loadZScoreBaseline()
    }

    // MARK: - Process CGM Reading

    func processGlucose(
        rawBG: Double,
        at timestamp: Date,
        iob: Double?,
        isf: Double?,
        cr: Double?
    ) -> OrefSignalOutput {
        // Step 1: Run through Kalman filter + meal detection
        let signalOutput = signalProcessor.processReading(glucose: rawBG, at: timestamp)

        // Step 2: Calculate residual if IOB data is available
        var residualEntry: BGResidualCalculator.ResidualEntry?
        if let iob = iob, let isf = isf {
            residualEntry = residualCalculator.update(
                filteredBG: signalOutput.filter.bg,
                iob: iob,
                isf: isf,
                cr: cr,
                timestamp: timestamp
            )
        }

        // Step 3: Build combined output
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
            rawBG: rawBG
        )

        // Step 4: Log to signal store
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
            velocitySignalActive: signalOutput.mealSignal.velocitySignal
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
            "meal=\(output.mealDetectionConfidence.rawValue)"
        )

        return output
    }

    // MARK: - Process Garmin Data

    func processGarminData(_ snapshot: GarminContextSnapshot) {
        let metric = zScoreNormalizer.metricFromSnapshot(snapshot)
        let zScores = zScoreNormalizer.addDailyMetric(metric)

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

        // Persist the Z-score baseline for survival across app restarts
        saveZScoreBaseline()

        debug(
            .openAPS,
            "OrefSignal Z-Scores: HRV=\(zScores.hrvZScore.map { String(format: "%.2f", $0) } ?? "nil") " +
            "RHR=\(zScores.restingHRZScore.map { String(format: "%.2f", $0) } ?? "nil") " +
            "sleep=\(zScores.sleepScoreZScore.map { String(format: "%.2f", $0) } ?? "nil") " +
            "stress=\(zScores.stressSignalConfidence.rawValue) " +
            "baseline=\(zScores.baselineSize)d"
        )
    }

    // MARK: - Lifecycle

    func save() {
        _signalStore.save()
        saveZScoreBaseline()
    }

    func reset() {
        signalProcessor.reset()
        residualCalculator.reset()
        latestOutput = nil
    }

    // MARK: - Z-Score Baseline Persistence

    private static let zScoreBaselineFile = "oref_zscore_baseline.json"

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
}
