import CoreData
import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite("Smartwatch host: alerts, trends, presets and the watch bolus") struct SmartwatchHostTests {
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

    @MainActor @Test("Alerts and retractions reach the watch in the order Trio made them, from any thread") func watchAlertOrder() async {
        let order = WatchAlertForwardOrder()
        let received = Received()
        let last = await Task.detached {
            var last: Task<Void, Never>?
            for index in 0 ..< 200 {
                last = order.enqueue { received.values.append(index) }
            }
            return last
        }.value
        await last?.value
        #expect(received.values == Array(0 ..< 200))
    }

    @MainActor private final class Received {
        var values: [Int] = []
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

    @Test("oref's forecasts become one curve per type, 5 minutes apart, in a fixed order") func forecastCurves() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let curves = BaseSmartwatchHost.forecastCurves(
            ["uam": [140, 141], "cob": [140, 142, 145], "iob": [140, 137, 133], "zt": [140, 135]],
            start: start
        )
        let mgdL = { (curve: [PredictedGlucoseValue]) in curve.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) } }
        #expect(curves.map(mgdL) == [[140, 137, 133], [140, 135], [140, 142, 145], [140, 141]])
        #expect(curves[0].map(\.startDate) == [start, start.addingTimeInterval(300), start.addingTimeInterval(600)])
    }

    @Test("Forecasts oref didn't compute, or without a start, give no curves") func forecastCurvesMissing() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        // No COB without carbs, UAM off: only what oref computed.
        #expect(BaseSmartwatchHost.forecastCurves(["iob": [120], "zt": [118]], start: start).count == 2)
        #expect(BaseSmartwatchHost.forecastCurves(["iob": [], "zt": [118]], start: start).count == 1)
        #expect(BaseSmartwatchHost.forecastCurves([:], start: start).isEmpty)
        #expect(BaseSmartwatchHost.forecastCurves(["iob": [120]], start: nil).isEmpty)
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

    @Test("A watch bolus the pump accepted is answered as delivered, whatever happens after") func pumpOutcomeThenCancel() async {
        // LoopKit: deliverBolus returns once the pump accepted the bolus; it may still
        // be cancelled on the phone. Trio's enactBolus reports acceptance, then runs a
        // determination; a cancel then (cancelBolus, its own callback) or any later
        // report doesn't change or delay the watch's answer.
        let start = ContinuousClock.now
        let outcome = await BaseSmartwatchHost.pumpOutcome { callback in
            callback(true, "Bolus enacted successfully.")
            try? await Task.sleep(for: .seconds(30))
            callback(false, "Bolus cancelled")
        }
        #expect(outcome == .init(success: true, message: "Bolus enacted successfully."))
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("Closed loop only in closed mode and without a manual temp basal") func closedLoopFlag() {
        #expect(BaseSmartwatchHost.isClosedLoop(dosingMode: .closed, isManualTempBasal: false))
        #expect(!BaseSmartwatchHost.isClosedLoop(dosingMode: .closed, isManualTempBasal: true))
        for mode in [DosingMode.open, .lowGlucoseSuspend, .basalTesting] {
            #expect(!BaseSmartwatchHost.isClosedLoop(dosingMode: mode, isManualTempBasal: false), "\(mode)")
            #expect(!BaseSmartwatchHost.isClosedLoop(dosingMode: mode, isManualTempBasal: true), "\(mode)")
        }
    }

    @Test("A context read is logged when its answer changes, not when it repeats") func contextRecommendationLog() {
        var log = ContextRecommendationLog()
        // The plugin reads 0 g after every change; only a new answer is logged,
        // including a return to an earlier one.
        let logged = [0, 0, 0, 1.25, 1.25, 0].map { log.shouldLog($0) }
        #expect(logged == [true, false, false, true, false, true])
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

    private func pluginAlert(_ level: Alert.InterruptionLevel, manager: String = "SomePump") -> Alert {
        let content = Alert.Content(title: "Watch app missing", body: "Install it again.", acknowledgeActionButtonLabel: "OK")
        return Alert(
            identifier: identifier("watchAppMissing", manager: manager),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: level
        )
    }

    @Test("A watch plugin's alert is never critical") func watchPluginAlertCap() {
        #expect(
            BaseSmartwatchHost.watchPluginAlert(pluginAlert(.critical), from: "LupedSmartwatch").interruptionLevel ==
                .timeSensitive
        )
        #expect(
            BaseSmartwatchHost.watchPluginAlert(pluginAlert(.timeSensitive), from: "LupedSmartwatch").interruptionLevel ==
                .timeSensitive
        )
        #expect(BaseSmartwatchHost.watchPluginAlert(pluginAlert(.active), from: "LupedSmartwatch").interruptionLevel == .active)
    }

    @Test("A watch plugin's alert is its own, whatever manager it names") func watchPluginAlertIdentity() {
        // Naming Trio or a pump can't impersonate or retract their alerts.
        for manager in [BaseTrioAlertManager.managerIdentifier, "SomePump"] {
            let alert = BaseSmartwatchHost.watchPluginAlert(pluginAlert(.critical, manager: manager), from: "LupedSmartwatch")
            #expect(alert.identifier == identifier("watchAppMissing", manager: "LupedSmartwatch"))
            #expect(BaseSmartwatchHost.glucoseAlertType(of: alert.identifier) == nil)
        }
        #expect(
            BaseSmartwatchHost.watchPluginAlertIdentifier(identifier("watchAppMissing"), from: "LupedSmartwatch") ==
                identifier("watchAppMissing", manager: "LupedSmartwatch")
        )
        // Content, trigger and sound are the plugin's.
        let alert = BaseSmartwatchHost.watchPluginAlert(pluginAlert(.critical), from: "LupedSmartwatch")
        #expect(alert.foregroundContent == pluginAlert(.critical).foregroundContent)
        #expect(alert.backgroundContent == pluginAlert(.critical).backgroundContent)
        #expect(alert.trigger == .immediate)
    }

    @Test("Preset durations in minutes, none or 0 as indefinite") func presetDurations() {
        #expect(BaseSmartwatchHost.duration(minutes: NSDecimalNumber(value: 60), indefinite: false) == .finite(60 * 60))
        #expect(BaseSmartwatchHost.duration(minutes: NSDecimalNumber(value: 60), indefinite: true) == .indefinite)
        #expect(BaseSmartwatchHost.duration(minutes: NSDecimalNumber(value: 0), indefinite: false) == .indefinite)
        #expect(BaseSmartwatchHost.duration(minutes: nil, indefinite: false) == .indefinite)
    }

    @Test("Trend arrows match LoopKit's GlucoseTrend") func trends() {
        #expect(BloodGlucose.Direction.tripleUp.glucoseTrend == .upUpUp)
        #expect(BloodGlucose.Direction.doubleUp.glucoseTrend == .upUpUp)
        #expect(BloodGlucose.Direction.singleUp.glucoseTrend == .upUp)
        #expect(BloodGlucose.Direction.fortyFiveUp.glucoseTrend == .up)
        #expect(BloodGlucose.Direction.flat.glucoseTrend == .flat)
        #expect(BloodGlucose.Direction.fortyFiveDown.glucoseTrend == .down)
        #expect(BloodGlucose.Direction.singleDown.glucoseTrend == .downDown)
        #expect(BloodGlucose.Direction.doubleDown.glucoseTrend == .downDownDown)
        #expect(BloodGlucose.Direction.tripleDown.glucoseTrend == .downDownDown)
        #expect(BloodGlucose.Direction.notComputable.glucoseTrend == nil)
        #expect(BloodGlucose.Direction.rateOutOfRange.glucoseTrend == nil)
    }
}

@Suite("Smartwatch host: Trio's readings as LoopKit samples", .serialized) struct SmartwatchHostGlucoseTests {
    let context: NSManagedObjectContext

    init() async throws {
        context = try await CoreDataStack.createForTests().newTaskContext()
    }

    private func sample(
        _ glucose: Int16,
        direction: String?,
        isManual: Bool = false,
        date: Date? = Date()
    ) async -> StoredGlucoseSample? {
        await context.perform {
            let stored = GlucoseStored(context: context)
            stored.glucose = glucose
            stored.direction = direction
            stored.isManual = isManual
            stored.date = date
            stored.id = UUID()
            return BaseSmartwatchHost.glucoseSample(from: stored)
        }
    }

    @Test("A reading in mg/dL with its date, id and arrow") func cgmReading() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let reading = try #require(await sample(126, direction: "SingleUp", date: date))
        #expect(reading.quantity == LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 126))
        #expect(reading.quantity.doubleValue(for: .millimolesPerLiter) > 6.9)
        #expect(reading.startDate == date)
        #expect(reading.trend == .upUp)
        #expect(reading.syncIdentifier != nil)
        #expect(!reading.wasUserEntered)
        #expect(!reading.isDisplayOnly)
    }

    @Test("No arrow for a missing or uncomputable direction") func noArrow() async throws {
        #expect(try #require(await sample(100, direction: nil)).trend == nil)
        #expect(try #require(await sample(100, direction: "NOT COMPUTABLE")).trend == nil)
        #expect(try #require(await sample(100, direction: "RATE OUT OF RANGE")).trend == nil)
        #expect(try #require(await sample(100, direction: "TripleDown")).trend == .downDownDown)
    }

    @Test("A hand-entered reading is marked as such") func manualReading() async throws {
        #expect(try #require(await sample(140, direction: nil, isManual: true)).wasUserEntered)
    }

    @Test("A reading without a date is left out") func noDate() async {
        #expect(await sample(100, direction: "Flat", date: nil) == nil)
    }
}

/// A watch manager that records what the host tells it changed.
private final class FakeSmartwatchManager: SmartwatchManager {
    weak var smartwatchManagerDelegate: SmartwatchManagerDelegate?
    @MainActor private(set) var changes: [SmartwatchHostDataChange] = []

    let pluginIdentifier = "FakeSmartwatch"
    let localizedTitle = "Fake watch"
    let isOnboarded = true
    let inSignalLoss = false
    let isInoperable = false
    var rawState: RawStateValue { [:] }
    var debugDescription: String { "FakeSmartwatchManager" }

    init() {}
    init?(rawState _: RawStateValue) {}

    @MainActor func hostDataDidChange(_ changes: SmartwatchHostDataChange) {
        self.changes.append(changes)
    }

    func acknowledgeAlert(alertIdentifier _: Alert.AlertIdentifier) async throws {}
    func getSoundBaseURL() -> URL? { nil }
    func getSounds() -> [Alert.Sound] { [] }
}

@Suite("Smartwatch host: glucose display limits") struct SmartwatchDisplayLimitsTests {
    @Test("The display limits are Trio's low and high") func lowAndHigh() {
        let limits = BaseSmartwatchHost.displayLimits(low: 70, high: 180)
        #expect(limits?.low == LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 70))
        #expect(limits?.high == LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 180))
    }

    @Test("No display limits when low isn't below high") func lowNotBelowHigh() {
        #expect(BaseSmartwatchHost.displayLimits(low: 180, high: 180) == nil)
        #expect(BaseSmartwatchHost.displayLimits(low: 200, high: 100) == nil)
    }
}

@Suite("Smartwatch host: change signals") @MainActor struct SmartwatchChangeBatchTests {
    /// Lets the main queue run the batch's delivery.
    private func nextRunLoopTurns() async throws {
        for _ in 0 ..< 5 {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Signals in a row reach the watch manager once, merged") func merged() async throws {
        let manager = FakeSmartwatchManager()
        let batch = SmartwatchChangeBatch { manager }
        batch.signal(.glucose)
        batch.signal(.loop)
        batch.signal([.loop, .presets])
        #expect(manager.changes.isEmpty, "sent on the next run loop turn")
        try await nextRunLoopTurns()
        #expect(manager.changes == [[.glucose, .loop, .presets]])

        // A signal after delivery starts a new batch.
        batch.signal(.settings)
        batch.signal(.alertMute)
        try await nextRunLoopTurns()
        #expect(manager.changes == [[.glucose, .loop, .presets], [.settings, .alertMute]])
    }

    @Test("Nothing is sent without a watch manager, or after everything was sent") func noManagerOrDiscarded() async throws {
        let manager = FakeSmartwatchManager()
        var current: FakeSmartwatchManager?
        let batch = SmartwatchChangeBatch { current }
        batch.signal(.glucose)
        current = manager
        try await nextRunLoopTurns()
        #expect(manager.changes.isEmpty, "signalled before there was a watch manager")

        // refresh() tells the manager .all and drops what is pending.
        batch.signal(.loop)
        batch.discardPending()
        try await nextRunLoopTurns()
        #expect(manager.changes.isEmpty)
        batch.signal(.presets)
        try await nextRunLoopTurns()
        #expect(manager.changes == [.presets])
    }
}
