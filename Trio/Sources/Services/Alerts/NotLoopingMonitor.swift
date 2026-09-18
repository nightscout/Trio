import Combine
import Foundation
import LoopKit
import Swinject

/// Escalating watchdog for a stalled loop. On every successful loop the
/// pending alarms are retracted and a fresh ladder is armed: a Time-Sensitive
/// warning at 20, 40, 60, 80 and 100 minutes, then a Critical alarm at 120.
///
/// The whole ladder is armed up front rather than re-armed as each one fires.
/// `Alert.Trigger.delayed(interval:)` becomes a `UNTimeIntervalNotification-
/// Trigger`, so the OS owns every step and the Critical alarm still arrives
/// when iOS has suspended Trio — which is the overnight device-failure case
/// the Critical tier exists for. Re-arming as a chain, or counting loop
/// invocations, would both stop dead the moment the app stops running.
///
/// A loop that recovers at any point retracts the remaining steps, so a brief
/// connectivity drop never reaches Critical.
///
/// Replaces the legacy `scheduleMissingLoopNotifiactions` direct-UN path
/// in `BaseUserNotificationsManager`. The alert now flows through
/// `TrioAlertManager` and inherits tier config from Device Alarms
/// (Critical tier by default).
final class NotLoopingMonitor: Injectable {
    @Injected() private var apsManager: APSManager!
    @Injected() private var trioAlertManager: TrioAlertManager!
    @Injected() private var settingsManager: SettingsManager!

    /// Minutes of staleness for each Time-Sensitive warning step.
    private static let warningMinutes: [Int] = [20, 40, 60, 80, 100]

    /// Minutes of staleness before the alarm escalates to Critical. Two hours
    /// of no automated dosing, which is the window discussed for onset of harm
    /// from undelivered insulin.
    private static let criticalMinutes: Int = 120

    /// Critical escalation. Keeps the bare identifier so existing Critical
    /// tier configuration carries over.
    private static let alertID = Alert.Identifier(
        managerIdentifier: "trio.aps",
        alertIdentifier: "loop.notActive"
    )

    /// One identifier per warning step — a single identifier cannot hold more
    /// than one pending notification, the later `add` would replace the earlier.
    private static func warningID(_ step: Int) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: "trio.aps", alertIdentifier: "loop.notActive.w\(step)")
    }

    private static var allIDs: [Alert.Identifier] {
        [alertID] + warningMinutes.indices.map { warningID($0 + 1) }
    }

    private var subscriptions = Set<AnyCancellable>()

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe(to: apsManager.lastLoopDateSubject.eraseToAnyPublisher())
    }

    /// Publisher-only seam for tests: assigns the alert manager directly and
    /// subscribes to a supplied loop-date publisher, avoiding the need to stub
    /// the full `APSManager` protocol.
    init(loopDates: AnyPublisher<Date, Never>, trioAlertManager: TrioAlertManager) {
        self.trioAlertManager = trioAlertManager
        subscribe(to: loopDates)
    }

    private func subscribe(to loopDates: AnyPublisher<Date, Never>) {
        loopDates
            .sink { [weak self] _ in self?.rescheduleAlarm() }
            .store(in: &subscriptions)
    }

    private func rescheduleAlarm() {
        // Retract first — clears pending UN, modal timer, and throttler so the
        // next issueAlert isn't blocked by 5-min duplicate suppression.
        for identifier in Self.allIDs {
            trioAlertManager.retractAlert(identifier: identifier)
        }

        // Skip when Trio isn't expected to be auto-enacting: open loop, an
        // active manual temp basal, or a suspended pump. In all three the
        // user has implicitly told Trio "don't loop right now"; a "Not
        // Looping" alarm would just be noise. nil injection (publisher-only
        // test seam) passes so the existing tests still exercise the
        // retract/reschedule plumbing.
        guard settingsManager?.settings.dosingMode.automation != AutomationLevel.off,
              apsManager?.isManualTempBasal != true,
              apsManager?.isSuspended != true
        else { return }

        for (index, minutes) in Self.warningMinutes.enumerated() {
            issue(identifier: Self.warningID(index + 1), after: minutes, level: .timeSensitive)
        }
        issue(identifier: Self.alertID, after: Self.criticalMinutes, level: .critical)
    }

    /// The catalog decides the interruption level for `trio.aps` alerts, so the
    /// level passed here only matters if the entry is ever removed.
    private func issue(identifier: Alert.Identifier, after minutes: Int, level: Alert.InterruptionLevel) {
        let content = Alert.Content(
            title: String(localized: "Trio Not Active"),
            body: String(
                format: String(localized: "Last loop was more than %d min ago"),
                minutes
            ),
            acknowledgeActionButtonLabel: String(localized: "OK")
        )
        let alert = Alert(
            identifier: identifier,
            foregroundContent: content,
            backgroundContent: content,
            trigger: .delayed(interval: TimeInterval(minutes * 60)),
            interruptionLevel: level,
            sound: .sound(name: "honk.caf")
        )
        trioAlertManager.issueAlert(alert)
    }
}
