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
