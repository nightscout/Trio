import Combine
import Foundation
import LoopKit
import Swinject

/// Issues a `.notLooping` alarm if no successful loop completes within the
/// configured grace period (default 20 minutes). On every successful loop
/// the pending alarm is retracted and a fresh delayed alarm is rescheduled
/// — using `Alert.Trigger.delayed(interval:)` so it fires via UN even if
/// the app is suspended.
///
/// Replaces the legacy `scheduleMissingLoopNotifiactions` direct-UN path
/// in `BaseUserNotificationsManager`. The alert now flows through
/// `TrioAlertManager` and inherits tier config from Device Alarms
/// (Critical tier by default).
final class NotLoopingMonitor: Injectable {
    @Injected() private var apsManager: APSManager!
    @Injected() private var trioAlertManager: TrioAlertManager!

    /// Minutes of staleness before the alarm fires. Mirrors the legacy
    /// `firstInterval` (20 min) — the second 40-min reminder is dropped;
    /// retract-on-loop semantics make it redundant.
    private static let gracePeriodMinutes: Int = 20

    private static let alertID = Alert.Identifier(
        managerIdentifier: "trio.aps",
        alertIdentifier: "loop.notActive"
    )

    private var subscriptions = Set<AnyCancellable>()

    init(resolver: Resolver) {
        injectServices(resolver)
        apsManager.lastLoopDateSubject
            .sink { [weak self] _ in self?.rescheduleAlarm() }
            .store(in: &subscriptions)
    }

    private func rescheduleAlarm() {
        // Retract first — clears pending UN, modal timer, and throttler so the
        // next issueAlert isn't blocked by 5-min duplicate suppression.
        trioAlertManager.retractAlert(identifier: Self.alertID)

        let content = Alert.Content(
            title: String(localized: "Trio Not Active"),
            body: String(
                format: String(localized: "Last loop was more than %d min ago"),
                Self.gracePeriodMinutes
            ),
            acknowledgeActionButtonLabel: String(localized: "OK")
        )
        let alert = Alert(
            identifier: Self.alertID,
            foregroundContent: content,
            backgroundContent: content,
            trigger: .delayed(interval: TimeInterval(Self.gracePeriodMinutes * 60)),
            interruptionLevel: .critical,
            sound: .sound(name: "honk.caf")
        )
        trioAlertManager.issueAlert(alert)
    }
}
