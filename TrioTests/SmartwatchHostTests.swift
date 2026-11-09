import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite("Smartwatch host: alert and trend mapping") struct SmartwatchHostTests {
    private func identifier(_ alertIdentifier: String, manager: String = BaseTrioAlertManager.managerIdentifier)
        -> Alert.Identifier
    {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertIdentifier)
    }

    @Test("Trio glucose alerts map to the watch's alert types") func glucoseAlertTypes() {
        let uuid = UUID().uuidString
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("glucose.urgentLow.\(uuid)")) == .urgentLow)
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("glucose.low.\(uuid)")) == .low)
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("glucose.high.\(uuid)")) == .high)
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("glucose.forecastedLow.\(uuid)")) == .predictedLow)
    }

    @Test("Other alerts are not glucose alerts") func otherAlerts() {
        let uuid = UUID().uuidString
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("glucose.carbsRequired.\(uuid)")) == nil)
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("glucose.stale")) == nil)
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("notLooping")) == nil)
        #expect(BaseSmartwatchHost.glucoseAlertType(of: identifier("glucose.low.\(uuid)", manager: "SomeCGM")) == nil)
    }

    @Test("Watch carbs count until a determination includes them") func uncountedWatchCarbs() {
        let now = Date()
        let entry = BaseSmartwatchHost.WatchCarbEntry(date: now.addingTimeInterval(-60), grams: 20)
        // No determination, or one from before the entry: not in COB yet.
        #expect(BaseSmartwatchHost.uncountedWatchCarbs([entry], determinationDate: nil, now: now) == [entry])
        #expect(BaseSmartwatchHost.uncountedWatchCarbs(
            [entry],
            determinationDate: now.addingTimeInterval(-300),
            now: now
        ) == [entry])
        // A determination after the entry counts it in COB.
        #expect(BaseSmartwatchHost.uncountedWatchCarbs([entry], determinationDate: now, now: now).isEmpty)
        // Entries over 30 minutes old are dropped.
        let old = BaseSmartwatchHost.WatchCarbEntry(date: now.addingTimeInterval(-31 * 60), grams: 20)
        #expect(BaseSmartwatchHost.uncountedWatchCarbs([old], determinationDate: nil, now: now).isEmpty)
    }

    @Test("Restored watch alerts are cleared once, after Trio has had time to issue them again") func restoredAlertsTiming() {
        let launch = Date()
        var restored = BaseSmartwatchHost.RestoredWatchAlerts(launchedAt: launch)
        // Inside Trio's launch quiet window nothing is issued again yet. The first
        // update after it is when Trio issues again what still applies; clearing
        // waits a minute past that update, and happens once per launch.
        let clearedAt = [10, 40, 70, 100, 400].map { seconds in
            restored.glucoseDidUpdate(at: launch.addingTimeInterval(TimeInterval(seconds)))
        }
        #expect(clearedAt == [false, false, false, true, false])
        #expect(restored.isCleared)
    }

    @Test("Only glucose alarms not forwarded since launch are retracted") func restoredAlertsToRetract() {
        var restored = BaseSmartwatchHost.RestoredWatchAlerts(launchedAt: Date())
        let high = "Trio.glucose.high.\(UUID().uuidString)"
        let low = "Trio.glucose.low.\(UUID().uuidString)"
        restored.forwarded.insert(high)
        #expect(restored.toRetract(alarmAlerts: [high, low]) == [low])
        restored.forwarded.remove(high)
        #expect(restored.toRetract(alarmAlerts: [high, low]) == [high, low])
    }

    @Test("A recommendation leaves out insulin delivered after its determination") func recommendationLessDelivered() {
        // 18:23:24 determination recommends 1.85 U and enacts a 0.4 U SMB at 18:23:27.
        #expect(BaseSmartwatchHost.watchRecommendation(calculated: 1.85, deliveredSinceDetermination: 0.4) == 1.85 - 0.4)
        #expect(BaseSmartwatchHost.watchRecommendation(calculated: 1.85, deliveredSinceDetermination: 0) == 1.85)
        #expect(BaseSmartwatchHost.watchRecommendation(calculated: 0.3, deliveredSinceDetermination: 0.4) == 0)
    }

    @Test("A watch bolus right after an SMB passes Trio's checks as the watch asks them") func watchBolusAfterSMB() {
        // The watch host asks with a window starting now: a 0.4 U SMB 89 s earlier
        // no longer refuses a 1.45 U bolus, which Trio's 6-minute window would.
        let afterSMB = BolusSafetyInputs(maxBolus: 5, maxIOB: 10, currentIOB: 2, totalRecentBolus: 0.4)
        #expect(
            BolusSafetyEvaluator
                .evaluate(bolusAmount: 1.45, inputs: afterSMB) == .rejected(.recentBolusWithinWindow(totalRecent: 0.4))
        )
        let windowFromNow = BolusSafetyInputs(maxBolus: 5, maxIOB: 10, currentIOB: 2, totalRecentBolus: 0)
        #expect(BolusSafetyEvaluator.evaluate(bolusAmount: 1.45, inputs: windowFromNow) == .allowed)
        // Max bolus and max IOB still apply.
        #expect(BolusSafetyEvaluator.evaluate(bolusAmount: 6, inputs: windowFromNow) == .rejected(.exceedsMaxBolus(maxBolus: 5)))
        #expect(
            BolusSafetyEvaluator.evaluate(
                bolusAmount: 4,
                inputs: BolusSafetyInputs(maxBolus: 5, maxIOB: 5, currentIOB: 2, totalRecentBolus: 0)
            )
                == .rejected(.exceedsMaxIOB(currentIOB: 2, maxIOB: 5))
        )
    }

    @Test("Trio's bolus safety rejections reach the watch with a reason where there is one") func bolusSafetyErrors() {
        #expect(BaseSmartwatchHost.bolusError(for: .recentBolusWithinWindow(totalRecent: 0.4)) == .rateLimited)
        #expect(BaseSmartwatchHost.bolusError(for: .exceedsMaxBolus(maxBolus: 5)) == .exceedsMaximumBolus)
        #expect(BaseSmartwatchHost.bolusError(for: .iobUnavailable) == .refusedByHost("iobUnavailable"))
        if case .refusedByHost = BaseSmartwatchHost.bolusError(for: .exceedsMaxIOB(currentIOB: 9, maxIOB: 10)) {} else {
            Issue.record("max IOB should stay refusedByHost")
        }
    }

    @Test("A watch bolus that reached the pump counts for the time between boluses, delivered or not") func bolusAttempts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let token = UUID()
        let context = SmartwatchBolusContext(
            token: token,
            issuedAt: now.addingTimeInterval(-60),
            recommendedBolus: 2,
            maximumBolus: 5,
            supportedBolusVolumes: []
        )
        func evaluate(_ deliveries: [SmartwatchBolusPolicy.Delivery], at date: Date) -> Result<Double, SmartwatchBolusError> {
            SmartwatchBolusPolicy(
                isAllowed: true,
                currentContext: context,
                latestGlucoseDate: date.addingTimeInterval(-60),
                recentDeliveries: deliveries,
                roundToSupportedVolume: { $0 }
            ).evaluate(SmartwatchBolusRequest(units: 1, contextToken: token, requestedAt: date), now: date)
        }

        // A failed (possibly uncertain) delivery: the next watch bolus waits 5 minutes.
        let failed = BaseSmartwatchHost.bolusAttempted(at: now, in: [])
        #expect(evaluate(failed, at: now.addingTimeInterval(60)) == .failure(.rateLimited))
        #expect(evaluate(failed, at: now.addingTimeInterval(5 * 60 + 1)) == .success(1))
        // ...and adds nothing to the daily total.
        #expect(failed.reduce(0) { $0 + $1.units } == 0)

        // A delivered one replaces its attempt with its units.
        let delivered = BaseSmartwatchHost.bolusDelivered(1.5, attemptedAt: now, in: failed)
        #expect(delivered == [SmartwatchBolusPolicy.Delivery(date: now, units: 1.5)])
        #expect(evaluate(delivered, at: now.addingTimeInterval(60)) == .failure(.rateLimited))
    }

    @Test("A watch bolus is answered when the pump reports, not after the determination that follows") func pumpOutcomeAtCallback() async {
        let start = ContinuousClock.now
        let outcome = await BaseSmartwatchHost.pumpOutcome { callback in
            callback(true, "Bolus enacted successfully.")
            // The determination after a manual bolus, longer than the watch waits.
            try? await Task.sleep(for: .seconds(60))
        }
        #expect(outcome == .init(success: true, message: "Bolus enacted successfully."))
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("A bolus path that never reports is a failure, and only its first report counts") func pumpOutcomeWithoutCallback() async {
        let silent = await BaseSmartwatchHost.pumpOutcome { _ in }
        #expect(silent == .init(success: false, message: "no answer from the pump"))
        let twice = await BaseSmartwatchHost.pumpOutcome { callback in
            callback(false, "Error! Bolus failed")
            callback(true, "Bolus enacted successfully.")
        }
        #expect(twice == .init(success: false, message: "Error! Bolus failed"))
    }

    @Test("Watch carbs stored while a determination ran count as in it, not twice") func carbsDuringADetermination() {
        // A loop starts calculating at 0 s (deliverAt) and fetches carbs at 2 s;
        // 40 g from the watch were stored at 1 s, so they are in its COB. The host
        // first sees the determination at 3 s.
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = BaseSmartwatchHost.WatchCarbEntry(date: start.addingTimeInterval(1), grams: 40)
        var sighting = BaseSmartwatchHost.DeterminationSighting()
        let seenAt = sighting.seenAt(calculatedAt: start, now: start.addingTimeInterval(3))
        #expect(
            BaseSmartwatchHost.uncountedWatchCarbs([entry], determinationDate: seenAt, now: start.addingTimeInterval(3))
                .isEmpty
        )
        // Compared with deliverAt they were added a second time.
        #expect(
            BaseSmartwatchHost
                .uncountedWatchCarbs([entry], determinationDate: start, now: start.addingTimeInterval(3)) == [entry]
        )
        // Carbs stored after the host saw the determination are not in it.
        let later = BaseSmartwatchHost.WatchCarbEntry(date: start.addingTimeInterval(4), grams: 10)
        #expect(
            BaseSmartwatchHost
                .uncountedWatchCarbs([later], determinationDate: seenAt, now: start.addingTimeInterval(5)) == [later]
        )
    }

    @Test("A determination is first seen once") func determinationSighting() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var sighting = BaseSmartwatchHost.DeterminationSighting()
        #expect(sighting.seenAt(calculatedAt: nil, now: start) == nil)
        #expect(sighting.seenAt(calculatedAt: start, now: start.addingTimeInterval(3)) == start.addingTimeInterval(3))
        #expect(
            sighting.seenAt(calculatedAt: start, now: start.addingTimeInterval(60)) == start.addingTimeInterval(3),
            "seen again later"
        )
        let next = start.addingTimeInterval(300)
        #expect(sighting.seenAt(calculatedAt: next, now: next.addingTimeInterval(2)) == next.addingTimeInterval(2))
    }

    @Test("Trend arrows match LoopKit's GlucoseTrend") func trends() {
        #expect(BloodGlucose.Direction.tripleUp.smartwatchTrend == .upUpUp)
        #expect(BloodGlucose.Direction.doubleUp.smartwatchTrend == .upUpUp)
        #expect(BloodGlucose.Direction.singleUp.smartwatchTrend == .upUp)
        #expect(BloodGlucose.Direction.fortyFiveUp.smartwatchTrend == .up)
        #expect(BloodGlucose.Direction.flat.smartwatchTrend == .flat)
        #expect(BloodGlucose.Direction.fortyFiveDown.smartwatchTrend == .down)
        #expect(BloodGlucose.Direction.singleDown.smartwatchTrend == .downDown)
        #expect(BloodGlucose.Direction.doubleDown.smartwatchTrend == .downDownDown)
        #expect(BloodGlucose.Direction.tripleDown.smartwatchTrend == .downDownDown)
        #expect(BloodGlucose.Direction.notComputable.smartwatchTrend == nil)
        #expect(BloodGlucose.Direction.rateOutOfRange.smartwatchTrend == nil)
    }
}
