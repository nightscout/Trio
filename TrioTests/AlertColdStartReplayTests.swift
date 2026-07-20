import Foundation
import LoopKit
import Swinject
import Testing

@testable import Trio

@Suite("Trio Alerts: AlertColdStartReplay decisions") struct AlertColdStartReplayTests {
    private let now = Date()

    private func entry(
        manager: String = "Omni",
        alert: String = "userPodExpiration",
        triggerType: Int16 = 0,
        triggerInterval: Decimal? = nil,
        issuedAgo: TimeInterval = 60,
        level: Decimal? = 2,
        title: String? = "Title",
        body: String? = "Body"
    ) -> AlertEntry {
        AlertEntry(
            alertIdentifier: alert,
            primitiveInterruptionLevel: level,
            issuedDate: now.addingTimeInterval(-issuedAgo),
            managerIdentifier: manager,
            triggerType: triggerType,
            triggerInterval: triggerInterval,
            contentTitle: title,
            contentBody: body
        )
    }

    private func decide(
        _ entry: AlertEntry,
        tierSnoozed: Bool = false,
        muted: Bool = false
    ) -> AlertColdStartReplay.Decision {
        AlertColdStartReplay.decision(
            for: entry,
            now: now,
            isTierSnoozed: { _ in tierSnoozed },
            isMuted: muted
        )
    }

    @Test("Elapsed delayed trigger replays as immediate") func elapsedDelayedBecomesImmediate() {
        let decision = decide(entry(
            manager: "trio.aps", alert: "loop.notActive",
            triggerType: 1, triggerInterval: 1200, issuedAgo: 25 * 60
        ))
        guard case let .replay(alert) = decision else {
            Issue.record("expected replay, got \(decision)")
            return
        }
        #expect(alert.trigger == .immediate)
    }

    @Test("Pending delayed trigger re-arms with remaining interval") func pendingDelayedKeepsRemainder() {
        let decision = decide(entry(
            manager: "trio.aps", alert: "loop.notActive",
            triggerType: 1, triggerInterval: 1200, issuedAgo: 5 * 60
        ))
        guard case let .replay(alert) = decision, case let .delayed(interval) = alert.trigger else {
            Issue.record("expected delayed replay, got \(decision)")
            return
        }
        #expect(abs(interval - 900) < 2)
    }

    @Test("Repeating trigger replays with original interval") func repeatingKeepsInterval() {
        let decision = decide(entry(triggerType: 2, triggerInterval: 900, issuedAgo: 3600))
        guard case let .replay(alert) = decision else {
            Issue.record("expected replay, got \(decision)")
            return
        }
        #expect(alert.trigger == .repeating(repeatInterval: 900))
    }

    @Test("Delayed trigger without interval is unreconstructable") func corruptTriggerSkips() {
        #expect(decide(entry(triggerType: 1, triggerInterval: nil)) == .skip)
    }

    @Test("Glucose-family entries acknowledge silently") func glucoseAcknowledgesSilently() {
        let glucose = entry(manager: "Trio", alert: "glucose.urgentLow.ABC-123")
        #expect(decide(glucose) == .acknowledgeSilently)
        let carbs = entry(manager: "Trio", alert: "glucose.carbsRequired.DEF-456")
        #expect(decide(carbs) == .acknowledgeSilently)
    }

    @Test("Catalog level override wins over stored level") func catalogOverridesStoredLevel() {
        // userPodExpiration is catalogued .active; stored says critical (3).
        let decision = decide(entry(level: 3))
        guard case let .replay(alert) = decision else {
            Issue.record("expected replay, got \(decision)")
            return
        }
        #expect(alert.interruptionLevel == .active)
    }

    @Test("Unknown identifier falls back to stored level, then timeSensitive") func levelFallbacks() {
        guard case let .replay(stored) = decide(entry(manager: "x", alert: "y", level: 3)) else {
            Issue.record("expected replay")
            return
        }
        #expect(stored.interruptionLevel == .critical)

        guard case let .replay(unstored) = decide(entry(manager: "x", alert: "y", level: nil)) else {
            Issue.record("expected replay")
            return
        }
        #expect(unstored.interruptionLevel == .timeSensitive)
    }

    @Test("Tier snooze skips catalog non-critical, critical pierces") func tierSnoozeGate() {
        #expect(decide(entry(), tierSnoozed: true) == .skip)
        let critical = entry(manager: "trio.aps", alert: "loop.notActive", issuedAgo: 60)
        if case .replay = decide(critical, tierSnoozed: true) {} else {
            Issue.record("critical should pierce tier snooze")
        }
    }

    @Test("Mute skips non-critical, critical pierces") func muteGate() {
        #expect(decide(entry(), muted: true) == .skip)
        let critical = entry(manager: "trio.aps", alert: "loop.notActive", issuedAgo: 60)
        if case .replay = decide(critical, muted: true) {} else {
            Issue.record("critical should pierce mute")
        }
    }

    @Test("Rebuilt alert carries content on both surfaces, no sound") func rebuiltAlertShape() {
        guard case let .replay(alert) = decide(entry()) else {
            Issue.record("expected replay")
            return
        }
        #expect(alert.sound == nil)
        #expect(alert.foregroundContent?.title == "Title")
        #expect(alert.foregroundContent == alert.backgroundContent)
    }

    @Test("newestPerIdentifier keeps first (newest) entry per identifier") func dedupe() {
        let newer = entry(issuedAgo: 60)
        let older = entry(issuedAgo: 3600)
        let other = entry(alert: "lowReservoir", issuedAgo: 120)
        let result = AlertColdStartReplay.newestPerIdentifier([newer, other, older])
        #expect(result == [newer, other])
    }
}

@Suite("Trio Alerts: AlertHistoryStorage acknowledgement") struct AlertHistoryStorageAckTests {
    private func makeStorage() -> (BaseAlertHistoryStorage, UserDefaults) {
        let suiteName = "AlertHistoryStorageAckTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let container = Container()
        container.register(FileStorage.self) { _ in BaseFileStorage() }
        container.register(Broadcaster.self) { _ in BaseBroadcaster() }
        let storage = BaseAlertHistoryStorage(resolver: container.synchronize(), userDefaults: defaults)
        return (storage, defaults)
    }

    private func entry(_ alert: String, issuedAgo: TimeInterval, manager: String = "Omni") -> AlertEntry {
        AlertEntry(
            alertIdentifier: alert,
            primitiveInterruptionLevel: 2,
            issuedDate: Date().addingTimeInterval(-issuedAgo),
            managerIdentifier: manager,
            triggerType: 0,
            triggerInterval: nil,
            contentTitle: "t",
            contentBody: "b"
        )
    }

    @Test("acknowledgeAllEntries marks every matching entry") func ackAllMatching() {
        let (storage, _) = makeStorage()
        storage.addAlert(entry("userPodExpiration", issuedAgo: 3600))
        storage.addAlert(entry("userPodExpiration", issuedAgo: 60))
        storage.addAlert(entry("lowReservoir", issuedAgo: 120))

        storage.acknowledgeAllEntries(managerIdentifier: "Omni", alertIdentifier: "userPodExpiration")

        let unacked = storage.unacknowledgedAlertsWithinLast24Hours()
        #expect(unacked.map(\.alertIdentifier) == ["lowReservoir"])
    }

    @Test("acknowledgeAllEntries matches manager identifier too") func ackScopedToManager() {
        let (storage, _) = makeStorage()
        storage.addAlert(entry("expiration", issuedAgo: 60, manager: "Omni"))
        storage.addAlert(entry("expiration", issuedAgo: 120, manager: "Medtrum"))

        storage.acknowledgeAllEntries(managerIdentifier: "Omni", alertIdentifier: "expiration")

        #expect(storage.unacknowledgedAlertsWithinLast24Hours().map(\.managerIdentifier) == ["Medtrum"])
    }

    @Test("removeAlert skips acknowledged entries") func removePreservesAcknowledged() {
        let (storage, defaults) = makeStorage()
        storage.addAlert(entry("userPodExpiration", issuedAgo: 60))
        storage.acknowledgeAllEntries(managerIdentifier: "Omni", alertIdentifier: "userPodExpiration")

        storage.removeAlert(identifier: "userPodExpiration")

        // Row survives as acknowledged history instead of being erased.
        let data = defaults.data(forKey: "openaps.monitor.alertHistory.data")!
        let persisted = try! JSONCoding.decoder.decode([AlertEntry].self, from: data)
        #expect(persisted.count == 1)
        #expect(persisted[0].acknowledgedDate != nil)
    }

    @Test("removeAlert deletes unacknowledged entry") func removeDeletesUnacknowledged() {
        let (storage, _) = makeStorage()
        storage.addAlert(entry("userPodExpiration", issuedAgo: 60))
        storage.removeAlert(identifier: "userPodExpiration")
        #expect(storage.unacknowledgedAlertsWithinLast24Hours().isEmpty)
    }
}
