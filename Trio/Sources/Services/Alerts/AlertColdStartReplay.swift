import Foundation
import LoopKit

/// Rebuilds unacknowledged history entries into presentable alerts at app
/// launch. In-app presentation state (`liveAlerts` + banner queue) dies with
/// the process, but every issued alert is persisted to `AlertHistoryStorage`
/// first — so a force-quit must not lose the user's only in-app surface for
/// acknowledging a device alert (e.g. a beeping pod).
///
/// Pure decision logic — mirrors `issueAlert`'s snooze/mute gates but skips
/// throttle, history recording, UN scheduling, and critical audio: the OS
/// still holds the original notifications across relaunch.
enum AlertColdStartReplay {
    enum Decision: Equatable {
        /// Re-present in-app (liveAlerts + banner scheduler).
        case replay(Alert)
        /// Glucose-family: `GlucoseAlertCoordinator` re-derives truth from
        /// live data after its launch quiet window and re-issues if still
        /// valid; a replayed entry could never be retracted on recovery.
        /// Mark it acknowledged so it doesn't linger unresolved.
        case acknowledgeSilently
        /// Gated (snooze/mute) or unreconstructable — entry stays
        /// unacknowledged and gets another chance next launch.
        case skip
    }

    /// Storage returns newest-first; keep the newest entry per identifier so
    /// a re-issued alert doesn't replay twice.
    static func newestPerIdentifier(_ entries: [AlertEntry]) -> [AlertEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert("\($0.managerIdentifier).\($0.alertIdentifier)").inserted }
    }

    static func decision(
        for entry: AlertEntry,
        now: Date,
        isTierSnoozed: (DeviceAlertSeverity) -> Bool,
        isMuted: Bool
    ) -> Decision {
        if GlucoseAlertType(slug: entry.alertIdentifier) != nil { return .acknowledgeSilently }

        // Rebuild the trigger relative to issuance: elapsed delayed →
        // immediate, pending delayed → remaining interval (keeps the
        // not-looping watchdog armed instead of blasting at launch).
        guard let trigger = try? Alert.Trigger(
            storedType: entry.triggerType,
            storedInterval: entry.triggerInterval.map { NSDecimalNumber(decimal: $0) },
            storageDate: entry.issuedDate,
            now: now
        ) else { return .skip }

        let identifier = Alert.Identifier(
            managerIdentifier: entry.managerIdentifier,
            alertIdentifier: entry.alertIdentifier
        )
        let catalogEntry = AlertCatalogRegistry.lookup(identifier)
        let level = catalogEntry?.interruptionLevel
            ?? entry.primitiveInterruptionLevel
            .flatMap { Alert.InterruptionLevel(storedValue: NSDecimalNumber(decimal: $0)) }
            ?? .timeSensitive

        // Same gates as issueAlert: tier snooze for catalog-known device
        // alerts, global mute for everything non-critical.
        if let tier = DeviceAlertSeverity(level: level),
           catalogEntry != nil,
           tier != .critical,
           isTierSnoozed(tier)
        {
            return .skip
        }
        if level != .critical, isMuted { return .skip }

        // The banner drops alerts without foregroundContent, so mirror the
        // stored content into both slots. The ack label is required non-nil
        // but rendered by neither surface.
        let content = Alert.Content(
            title: entry.contentTitle ?? "",
            body: entry.contentBody ?? "",
            acknowledgeActionButtonLabel: String(localized: "OK")
        )
        return .replay(Alert(
            identifier: identifier,
            foregroundContent: content,
            backgroundContent: content,
            trigger: trigger,
            interruptionLevel: level
        ))
    }
}
