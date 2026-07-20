import Combine
import Foundation
import LoopKit
import Testing
import UserNotifications

@testable import Trio

/// Records `issueAlert` / `retractAlert` calls in order so tests can assert
/// the retract-then-issue re-arm semantics of `NotLoopingMonitor`. Every
/// other `TrioAlertManager` member is a no-op stub.
final class SpyAlertManager: TrioAlertManager {
    enum Call: Equatable {
        case retract(Alert.Identifier)
        case issue(Alert)
    }

    private(set) var callLog: [Call] = []
    private(set) var issuedAlerts: [Alert] = []
    private(set) var retractedIdentifiers: [Alert.Identifier] = []

    func issueAlert(_ alert: Alert) {
        callLog.append(.issue(alert))
        issuedAlerts.append(alert)
    }

    func retractAlert(identifier: Alert.Identifier) {
        callLog.append(.retract(identifier))
        retractedIdentifiers.append(identifier)
    }

    // MARK: - No-op stubs

    func register(responder _: AlertResponder, for _: String) {}
    func register(soundVendor _: AlertSoundVendor, for _: String) {}
    func unregister(managerIdentifier _: String) {}

    func handleAcknowledgement(identifier _: Alert.Identifier) {}
    func handleNotificationResponse(_: UNNotificationResponse) {}
    func acknowledgeAllOutstanding() {}
    func replayUnacknowledgedAlerts() {}
    @MainActor func applySnooze(for _: TimeInterval) async {}
    func clearPendingNonCriticalNotifications() {}

    var muter: AlertMuter { AlertMuter() }
    let modalScheduler = TrioModalAlertScheduler()

    func soundURL(for _: Alert) -> URL? { nil }
}

@Suite("Trio Alerts: NotLoopingMonitor") struct NotLoopingMonitorTests {
    /// Reconstructed locally from the private static constant in the source.
    private let expectedID = Alert.Identifier(
        managerIdentifier: "trio.aps",
        alertIdentifier: "loop.notActive"
    )

    @Test(
        "A single loop success retracts then issues a fresh delayed critical alarm"
    ) func singleLoopSuccessRetractsThenIssuesDelayedCritical() {
        let subject = PassthroughSubject<Date, Never>()
        let spy = SpyAlertManager()
        let monitor = NotLoopingMonitor(loopDates: subject.eraseToAnyPublisher(), trioAlertManager: spy)

        subject.send(Date())

        #expect(spy.callLog.count == 2)
        guard spy.issuedAlerts.count == 1 else {
            Issue.record("expected exactly one issued alert")
            return
        }
        let issued = spy.issuedAlerts[0]
        #expect(spy.callLog == [.retract(expectedID), .issue(issued)])
        #expect(issued.identifier == expectedID)
        #expect(issued.trigger == .delayed(interval: 1200))
        #expect(issued.interruptionLevel == .critical)

        _ = monitor // retain through the synchronous send
    }

    @Test("Retract is logged before issue on each re-arm") func retractHappensBeforeIssue() {
        let subject = PassthroughSubject<Date, Never>()
        let spy = SpyAlertManager()
        let monitor = NotLoopingMonitor(loopDates: subject.eraseToAnyPublisher(), trioAlertManager: spy)

        subject.send(Date())

        let retractIndex = spy.callLog.firstIndex { if case .retract = $0 { return true }
            return false }
        let issueIndex = spy.callLog.firstIndex { if case .issue = $0 { return true }
            return false }
        #expect(retractIndex != nil)
        #expect(issueIndex != nil)
        if let r = retractIndex, let i = issueIndex {
            #expect(r < i)
        }

        _ = monitor
    }

    @Test("Two successive loop successes re-arm the alarm each time") func twoSuccessiveLoopSuccessesReArmEachTime() {
        let subject = PassthroughSubject<Date, Never>()
        let spy = SpyAlertManager()
        let monitor = NotLoopingMonitor(loopDates: subject.eraseToAnyPublisher(), trioAlertManager: spy)

        subject.send(Date())
        subject.send(Date())

        #expect(spy.callLog.count == 4)
        guard spy.issuedAlerts.count == 2 else {
            Issue.record("expected exactly two issued alerts")
            return
        }
        #expect(spy.callLog == [
            .retract(expectedID),
            .issue(spy.issuedAlerts[0]),
            .retract(expectedID),
            .issue(spy.issuedAlerts[1])
        ])
        for issued in spy.issuedAlerts {
            #expect(issued.trigger == .delayed(interval: 1200))
            #expect(issued.interruptionLevel == .critical)
        }

        _ = monitor
    }

    @Test("Issued trigger is delayed, not immediate") func issuedTriggerIsDelayedNotImmediate() {
        let subject = PassthroughSubject<Date, Never>()
        let spy = SpyAlertManager()
        let monitor = NotLoopingMonitor(loopDates: subject.eraseToAnyPublisher(), trioAlertManager: spy)

        subject.send(Date())

        guard let issued = spy.issuedAlerts.first else {
            Issue.record("expected an issued alert")
            return
        }
        #expect(issued.trigger == .delayed(interval: 1200))
        #expect(issued.trigger != .immediate)

        _ = monitor
    }
}
