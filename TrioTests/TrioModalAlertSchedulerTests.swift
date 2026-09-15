import Foundation
import LoopKit
import Testing
@testable import Trio

@MainActor
@Suite("Trio Alerts: TrioModalAlertScheduler clearNonCriticalBanners") struct TrioModalAlertSchedulerClearTests {
    private func makeAlert(
        interruptionLevel: LoopKit.Alert.InterruptionLevel,
        identifier: String
    ) -> LoopKit.Alert {
        let content = LoopKit.Alert.Content(
            title: "Title",
            body: "Body",
            acknowledgeActionButtonLabel: "OK"
        )
        return LoopKit.Alert(
            identifier: LoopKit.Alert.Identifier(
                managerIdentifier: "trio.test",
                alertIdentifier: identifier
            ),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: interruptionLevel,
            sound: nil
        )
    }

    @Test("Mixed queue keeps only critical") func mixedKeepsOnlyCritical() {
        let scheduler = TrioModalAlertScheduler()
        scheduler.seedForTesting([
            makeAlert(interruptionLevel: .critical, identifier: "c"),
            makeAlert(interruptionLevel: .timeSensitive, identifier: "ts"),
            makeAlert(interruptionLevel: .active, identifier: "a")
        ])
        scheduler.clearNonCriticalBanners()
        #expect(scheduler.active.map(\.identifier.alertIdentifier) == ["c"])
    }

    @Test("All-critical queue is unchanged and order-preserved") func allCriticalUnchanged() {
        let scheduler = TrioModalAlertScheduler()
        scheduler.seedForTesting([
            makeAlert(interruptionLevel: .critical, identifier: "c1"),
            makeAlert(interruptionLevel: .critical, identifier: "c2")
        ])
        scheduler.clearNonCriticalBanners()
        #expect(scheduler.active.map(\.identifier.alertIdentifier) == ["c1", "c2"])
    }

    @Test("Empty queue stays empty") func emptyStaysEmpty() {
        let scheduler = TrioModalAlertScheduler()
        scheduler.seedForTesting([])
        scheduler.clearNonCriticalBanners()
        #expect(scheduler.active.isEmpty)
    }

    @Test("All-non-critical queue becomes empty") func allNonCriticalBecomesEmpty() {
        let scheduler = TrioModalAlertScheduler()
        scheduler.seedForTesting([
            makeAlert(interruptionLevel: .timeSensitive, identifier: "ts"),
            makeAlert(interruptionLevel: .active, identifier: "a")
        ])
        scheduler.clearNonCriticalBanners()
        #expect(scheduler.active.isEmpty)
    }
}

@Suite("Trio Alerts: TrioModalAlertScheduler fire-gate") struct TrioModalAlertSchedulerFireGateTests {
    @Test("Critical, active, snoozed -> insert") func criticalActiveSnoozedInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .critical,
                isAlertActive: true,
                isSnoozeActive: true
            ) == .insert
        )
    }

    @Test("TimeSensitive, active, snoozed -> suppressKeepPending") func timeSensitiveActiveSnoozedSuppresses() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .timeSensitive,
                isAlertActive: true,
                isSnoozeActive: true
            ) == .suppressKeepPending
        )
    }

    @Test("TimeSensitive, active, not snoozed -> insert") func timeSensitiveActiveNotSnoozedInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .timeSensitive,
                isAlertActive: true,
                isSnoozeActive: false
            ) == .insert
        )
    }

    @Test("Active, active, snoozed -> suppressKeepPending") func activeActiveSnoozedSuppresses() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .active,
                isAlertActive: true,
                isSnoozeActive: true
            ) == .suppressKeepPending
        )
    }

    @Test("TimeSensitive, inactive, not snoozed -> dropStale") func timeSensitiveInactiveDropsStale() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .timeSensitive,
                isAlertActive: false,
                isSnoozeActive: false
            ) == .dropStale
        )
    }

    @Test("Critical, inactive, snoozed -> dropStale") func criticalInactiveDropsStale() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .critical,
                isAlertActive: false,
                isSnoozeActive: true
            ) == .dropStale
        )
    }

    @Test("Active, inactive, snoozed -> dropStale") func activeInactiveDropsStale() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .active,
                isAlertActive: false,
                isSnoozeActive: true
            ) == .dropStale
        )
    }

    // nil-responder modeled as isAlertActive defaulting true and
    // isSnoozeActive defaulting false (== true comparison yields false).
    @Test("Nil responder, timeSensitive -> insert") func nilResponderTimeSensitiveInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .timeSensitive,
                isAlertActive: true,
                isSnoozeActive: false
            ) == .insert
        )
    }

    @Test("Nil responder, critical -> insert") func nilResponderCriticalInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                interruptionLevel: .critical,
                isAlertActive: true,
                isSnoozeActive: false
            ) == .insert
        )
    }
}
