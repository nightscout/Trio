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
    @Test("Piercing, active, snoozed -> insert") func piercingActiveSnoozedInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: true,
                isAlertActive: true,
                isSnoozeActive: true
            ) == .insert
        )
    }

    @Test("Non-piercing, active, snoozed -> suppressKeepPending") func nonPiercingActiveSnoozedSuppresses() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: false,
                isAlertActive: true,
                isSnoozeActive: true
            ) == .suppressKeepPending
        )
    }

    @Test("Non-piercing, active, not snoozed -> insert") func nonPiercingActiveNotSnoozedInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: false,
                isAlertActive: true,
                isSnoozeActive: false
            ) == .insert
        )
    }

    @Test("Non-piercing, inactive, not snoozed -> dropStale") func nonPiercingInactiveDropsStale() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: false,
                isAlertActive: false,
                isSnoozeActive: false
            ) == .dropStale
        )
    }

    @Test("Piercing, inactive, snoozed -> dropStale") func piercingInactiveDropsStale() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: true,
                isAlertActive: false,
                isSnoozeActive: true
            ) == .dropStale
        )
    }

    @Test("Non-piercing, inactive, snoozed -> dropStale") func nonPiercingInactiveSnoozedDropsStale() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: false,
                isAlertActive: false,
                isSnoozeActive: true
            ) == .dropStale
        )
    }

    // nil-responder modeled as isAlertActive defaulting true and
    // isSnoozeActive defaulting false (== true comparison yields false).
    @Test("Nil responder, non-piercing -> insert") func nilResponderNonPiercingInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: false,
                isAlertActive: true,
                isSnoozeActive: false
            ) == .insert
        )
    }

    @Test("Nil responder, piercing -> insert") func nilResponderPiercingInserts() {
        #expect(
            TrioModalAlertScheduler.shouldInsertOnFire(
                piercesSnooze: true,
                isAlertActive: true,
                isSnoozeActive: false
            ) == .insert
        )
    }
}
