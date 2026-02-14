import Combine
import Foundation
import Swinject

/// SmartSenseManager computes the blended sensitivity ratio from Garmin health data and oref's autosens.
///
/// Pipeline:
/// 1. Fetch GarminContextSnapshot from Firestore
/// 2. Compute raw impact for each of the 10 Garmin health signals
/// 3. Apply user-configured weights (must sum to 100%) to produce Garmin composite
/// 4. Blend Garmin composite with autosens via master split
/// 5. Clamp to +-maxAdjustment (default +-20%)
/// 6. Produce final sensitivity ratio (1.0 + blendedAdjustment)
///
/// At dose time, the user can override the computed ratio via the sensitivity slider.
/// The override persists for overrideDurationHours (default 6h), then reverts to computed.
protocol SmartSenseManager {
    /// Compute the full SmartSense result for the current moment.
    func computeSensitivity(autosensRatio: Decimal) async -> SmartSenseResult

    /// Apply a per-dose override. Persists for the configured duration.
    func applyOverride(computedRatio: Double, userRatio: Double)

    /// Get the currently active override, if any.
    var activeOverride: SmartSenseOverride? { get }

    /// The effective sensitivity ratio right now (override if active, else last computed).
    var currentEffectiveRatio: Double { get }

    /// Latest computed result (may be nil if never computed).
    var latestResult: SmartSenseResult? { get }
}

final class BaseSmartSenseManager: SmartSenseManager, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    private var _latestResult: SmartSenseResult?
    private var _activeOverride: SmartSenseOverride?
    private let firestoreService: GarminFirestoreService

    var latestResult: SmartSenseResult? { _latestResult }

    var activeOverride: SmartSenseOverride? {
        guard let override = _activeOverride, override.isActive else {
            _activeOverride = nil
            return nil
        }
        return override
    }

    var currentEffectiveRatio: Double {
        if let override = activeOverride {
            return override.overrideRatio
        }
        return _latestResult?.finalRatio ?? 1.0
    }

    init(resolver: Resolver) {
        firestoreService = GarminFirestoreService()
        injectServices(resolver)
    }

    // MARK: - Main Computation

    func computeSensitivity(autosensRatio: Decimal) async -> SmartSenseResult {
        let settings = settingsManager.settings.smartSenseSettings

        // Fetch Garmin data if enabled
        var snapshot: GarminContextSnapshot?
        if settings.garminEnabled {
            // Ensure Firebase is signed in (no-op if already authenticated)
            await GarminFirebaseManager.configureAndSignIn()

            if GarminFirebaseManager.isSignedIn {
                snapshot = await firestoreService.fetchContext()
            }
        }

        let garminAvailable = snapshot != nil

        // Compute Garmin factors
        let factors = computeGarminFactors(from: snapshot, weights: settings.weights, maxAdj: settings.maxAdjustment)
        let garminComposite = factors.reduce(0.0) { $0 + $1.weightedImpact }

        // Autosens contribution
        let autosensDouble = NSDecimalNumber(decimal: autosensRatio).doubleValue
        let autosensContribution = autosensDouble - 1.0

        // Blend using master split
        let effectiveGarminSplit = garminAvailable ? settings.garminSplit : 0.0
        let effectiveAutosenseSplit = garminAvailable ? (1.0 - settings.garminSplit) : 1.0

        let blended = (garminComposite * effectiveGarminSplit) + (autosensContribution * effectiveAutosenseSplit)
        let clamped = max(-settings.maxAdjustment, min(settings.maxAdjustment, blended))
        let finalRatio = 1.0 + clamped

        let result = SmartSenseResult(
            garminFactors: factors,
            garminComposite: garminComposite,
            autosensRatio: autosensDouble,
            autosensContribution: autosensContribution,
            masterSplit: SmartSenseResult.MasterSplit(
                garmin: effectiveGarminSplit,
                autosens: effectiveAutosenseSplit
            ),
            blendedSuggestion: clamped,
            finalRatio: finalRatio,
            garminDataAvailable: garminAvailable,
            garminDataTime: snapshot?.queryTime
        )

        _latestResult = result
        return result
    }

    // MARK: - Override

    func applyOverride(computedRatio: Double, userRatio: Double) {
        let settings = settingsManager.settings.smartSenseSettings
        let duration = settings.overrideDurationHours * 3600
        _activeOverride = SmartSenseOverride(
            overrideRatio: userRatio,
            computedRatio: computedRatio,
            wasModified: abs(userRatio - computedRatio) > 0.005,
            appliedAt: Date(),
            expiresAt: Date().addingTimeInterval(duration)
        )
        debug(.service, "SmartSense: override applied — ratio \(userRatio) (computed was \(computedRatio)), expires in \(settings.overrideDurationHours)h")
    }

    // MARK: - Garmin Factor Computation

    /// Compute the 10 Garmin factors from a snapshot, using the weight budget system.
    ///
    /// Each signal computes a normalized impact in [-1, +1] where:
    ///   positive = more resistant (needs more insulin)
    ///   negative = more sensitive (needs less insulin)
    ///
    /// The weighted impact is: normalized * weight * maxAdjustment
    /// So if sleep has weight 0.30 and maxAdjustment 0.20, sleep can contribute up to +-6%.
    private func computeGarminFactors(
        from ctx: GarminContextSnapshot?,
        weights: SmartSenseWeights,
        maxAdj: Double
    ) -> [SmartSenseResult.FactorContribution] {
        guard let ctx = ctx else {
            return [SmartSenseResult.FactorContribution(
                factor: "Garmin Data", value: "Unavailable", rawImpact: 0, weight: 0, weightedImpact: 0
            )]
        }

        var results: [SmartSenseResult.FactorContribution] = []

        // 1. Sleep Score (0-100, low = resistant)
        let sleepScoreResult = computeSleepScore(ctx.sleepScoreValue)
        results.append(makeContribution(
            factor: "Sleep Score",
            value: ctx.sleepScoreValue.map { "\($0)/100" } ?? "N/A",
            normalized: sleepScoreResult,
            weight: weights.sleepScore,
            maxAdj: maxAdj
        ))

        // 2. Sleep Duration
        let sleepDurResult = computeSleepDuration(ctx.totalSleepMinutes)
        results.append(makeContribution(
            factor: "Sleep Duration",
            value: ctx.totalSleepMinutes.map { "\($0 / 60)h \($0 % 60)m" } ?? "N/A",
            normalized: sleepDurResult,
            weight: weights.sleepDuration,
            maxAdj: maxAdj
        ))

        // 3. Body Battery (0-100, low = resistant)
        let bbResult = computeBodyBattery(ctx.currentBodyBattery)
        results.append(makeContribution(
            factor: "Body Battery",
            value: ctx.currentBodyBattery.map { "\($0)/100" } ?? "N/A",
            normalized: bbResult,
            weight: weights.bodyBattery,
            maxAdj: maxAdj
        ))

        // 4. Current Stress (0-100, high = resistant)
        let stressResult = computeCurrentStress(ctx.currentStressLevel)
        results.append(makeContribution(
            factor: "Current Stress",
            value: ctx.currentStressLevel.map { "\($0)/100" } ?? "N/A",
            normalized: stressResult,
            weight: weights.currentStress,
            maxAdj: maxAdj
        ))

        // 5. Average Stress
        let avgStressResult = computeAvgStress(ctx.averageStressLevel)
        results.append(makeContribution(
            factor: "Avg Stress",
            value: ctx.averageStressLevel.map { "\($0)/100" } ?? "N/A",
            normalized: avgStressResult,
            weight: weights.avgStress,
            maxAdj: maxAdj
        ))

        // 6. Resting HR Delta
        let rhrResult = computeRestingHRDelta(ctx.restingHRDelta)
        results.append(makeContribution(
            factor: "Resting HR Delta",
            value: ctx.restingHRDelta.map { "\($0 > 0 ? "+" : "")\($0) bpm" } ?? "N/A",
            normalized: rhrResult,
            weight: weights.restingHRDelta,
            maxAdj: maxAdj
        ))

        // 7. HRV Delta
        let hrvResult = computeHRVDelta(ctx.hrvDeltaPercent)
        results.append(makeContribution(
            factor: "HRV Delta",
            value: ctx.hrvDeltaPercent.map { String(format: "%+.0f%%", $0) } ?? "N/A",
            normalized: hrvResult,
            weight: weights.hrvDelta,
            maxAdj: maxAdj
        ))

        // 8. Yesterday Activity
        let yActResult = computeYesterdayActivity(ctx.yesterdayActiveKilocalories)
        results.append(makeContribution(
            factor: "Yesterday Activity",
            value: ctx.yesterdayActiveKilocalories.map { "\($0) cal" } ?? "N/A",
            normalized: yActResult,
            weight: weights.yesterdayActivity,
            maxAdj: maxAdj
        ))

        // 9. Today Activity
        let tActResult = computeTodayActivity(ctx.activeKilocalories)
        results.append(makeContribution(
            factor: "Today Activity",
            value: ctx.activeKilocalories.map { "\($0) cal" } ?? "N/A",
            normalized: tActResult,
            weight: weights.todayActivity,
            maxAdj: maxAdj
        ))

        // 10. Vigorous Exercise (yesterday)
        let vigResult = computeVigorousExercise(ctx.yesterdayVigorousMinutes)
        results.append(makeContribution(
            factor: "Vigorous Exercise",
            value: ctx.yesterdayVigorousMinutes.map { "\($0) min" } ?? "N/A",
            normalized: vigResult,
            weight: weights.vigorousExercise,
            maxAdj: maxAdj
        ))

        return results
    }

    private func makeContribution(
        factor: String,
        value: String,
        normalized: Double,
        weight: Double,
        maxAdj: Double
    ) -> SmartSenseResult.FactorContribution {
        let budget = weight * maxAdj
        let weighted = normalized * budget
        return SmartSenseResult.FactorContribution(
            factor: factor,
            value: value,
            rawImpact: normalized,
            weight: weight,
            weightedImpact: weighted
        )
    }

    // MARK: - Signal Normalization Functions

    // Each returns a value in [-1, +1].
    // Positive = more resistant (needs more insulin).
    // Negative = more sensitive (needs less insulin).
    // Zero = neutral / no data.

    /// Sleep Score: 0-100, low = resistant
    /// <40: maximal resistance (1.0), 40-55: high (0.73), 55-70: moderate (0.36), 70-85: neutral, >=85: sensitive (-0.27)
    private func computeSleepScore(_ score: Int?) -> Double {
        guard let score = score else { return 0 }
        if score < 40 { return 1.0 }
        if score < 55 { return 0.73 }
        if score < 70 { return 0.36 }
        if score >= 85 { return -0.27 }
        return 0.0
    }

    /// Sleep Duration: short sleep = resistant
    /// <5h (300min): high resistance (1.0), 5-6h: moderate (0.60), 6-7h: mild (0.20), >=7h: neutral
    private func computeSleepDuration(_ minutes: Int?) -> Double {
        guard let minutes = minutes else { return 0 }
        if minutes < 300 { return 1.0 }
        if minutes < 360 { return 0.60 }
        if minutes < 420 { return 0.20 }
        return 0.0
    }

    /// Body Battery: 0-100, low = resistant
    /// <15: maximal (1.0), 15-30: high (0.67), 30-50: moderate (0.33), 50-75: neutral, >=75: sensitive (-0.33)
    private func computeBodyBattery(_ bb: Int?) -> Double {
        guard let bb = bb else { return 0 }
        if bb < 15 { return 1.0 }
        if bb < 30 { return 0.67 }
        if bb < 50 { return 0.33 }
        if bb >= 75 { return -0.33 }
        return 0.0
    }

    /// Current Stress: 0-100, high = resistant
    /// >75: high (1.0), 60-75: moderate (0.50), <60: neutral
    private func computeCurrentStress(_ stress: Int?) -> Double {
        guard let stress = stress, stress > 0 else { return 0 }
        if stress > 75 { return 1.0 }
        if stress > 60 { return 0.50 }
        return 0.0
    }

    /// Average Stress: 0-100, high = resistant
    /// >60: high (1.0), 45-60: moderate (0.67), <45: neutral
    private func computeAvgStress(_ avgStress: Int?) -> Double {
        guard let avgStress = avgStress, avgStress > 0 else { return 0 }
        if avgStress > 60 { return 1.0 }
        if avgStress > 45 { return 0.67 }
        return 0.0
    }

    /// Resting HR Delta from baseline: positive = elevated = resistant
    /// >12bpm: high (1.0), 8-12: moderate (0.67), 3-8: mild (0.20), <-5: sensitive (-0.33)
    private func computeRestingHRDelta(_ delta: Int?) -> Double {
        guard let delta = delta else { return 0 }
        if delta > 12 { return 1.0 }
        if delta > 8 { return 0.67 }
        if delta > 3 { return 0.20 }
        if delta < -5 { return -0.33 }
        return 0.0
    }

    /// HRV Delta % from baseline: negative = suppressed = resistant
    /// <-20%: high resistance (1.0), -10 to -20%: moderate (0.50), >+15%: sensitive (-0.50)
    private func computeHRVDelta(_ deltaPct: Double?) -> Double {
        guard let deltaPct = deltaPct else { return 0 }
        if deltaPct < -20 { return 1.0 }
        if deltaPct < -10 { return 0.50 }
        if deltaPct > 15 { return -0.50 }
        return 0.0
    }

    /// Yesterday Activity: high calories = more sensitive (negative = needs less insulin)
    /// >600cal: very sensitive (-1.0), >400: sensitive (-0.63), >250: mild (-0.38), else neutral
    private func computeYesterdayActivity(_ cal: Int?) -> Double {
        guard let cal = cal else { return 0 }
        if cal > 600 { return -1.0 }
        if cal > 400 { return -0.63 }
        if cal > 250 { return -0.38 }
        return 0.0
    }

    /// Today Activity: similar to yesterday but lower impact (user is still active)
    /// >400cal: sensitive (-1.0), >200: mild (-0.50), else neutral
    private func computeTodayActivity(_ cal: Int?) -> Double {
        guard let cal = cal else { return 0 }
        if cal > 400 { return -1.0 }
        if cal > 200 { return -0.50 }
        return 0.0
    }

    /// Vigorous Exercise yesterday: high intensity = more sensitive
    /// >45min: very sensitive (-1.0), >20min: sensitive (-0.50), else neutral
    private func computeVigorousExercise(_ minutes: Int?) -> Double {
        guard let minutes = minutes else { return 0 }
        if minutes > 45 { return -1.0 }
        if minutes > 20 { return -0.50 }
        return 0.0
    }
}
