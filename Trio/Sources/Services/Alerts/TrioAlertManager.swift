import Combine
import Foundation
import LoopKit
import Swinject
import UserNotifications

protocol TrioAlertManager: AnyObject {
    func issueAlert(_ alert: Alert)
    func retractAlert(identifier: Alert.Identifier)

    func register(responder: AlertResponder, for managerIdentifier: String)
    func register(soundVendor: AlertSoundVendor, for managerIdentifier: String)
    func unregister(managerIdentifier: String)

    func handleAcknowledgement(identifier: Alert.Identifier)
    func handleNotificationResponse(_ response: UNNotificationResponse)
    func acknowledgeAllOutstanding()
    /// Canonical snooze entry point used by every snooze surface:
    /// Snooze module, phone UN action, watch UN action, in-app banner.
    /// Persists snoozeUntilDate, mutes AlertMuter, clears any pending
    /// non-critical UNs, broadcasts `SnoozeObserver`.
    @MainActor func applySnooze(for duration: TimeInterval) async
    /// Removes pending + already-delivered non-critical user notifications
    /// posted via the new alert pipeline. Used internally when a snooze
    /// begins so previously-scheduled delayed alerts (e.g. not-looping)
    /// don't fire during the snooze window. Critical UNs are left in
    /// place — they pierce snooze by design.
    func clearPendingNonCriticalNotifications()

    var muter: AlertMuter { get }
    var modalScheduler: TrioModalAlertScheduler { get }

    func soundURL(for alert: Alert) -> URL?
}

final class BaseTrioAlertManager: TrioAlertManager, Injectable {
    private struct WeakRef {
        weak var ref: AnyObject?
    }

    static let managerIdentifier = "Trio"
    static let soundsDirectoryName = "Sounds"

    @Injected() private var alertHistoryStorage: AlertHistoryStorage!
    @Injected() private var broadcaster: Broadcaster!

    let muter: AlertMuter
    private let throttler: AlertThrottler
    private let soundLoader: AlertSoundLoader
    /// Created lazily on first main-actor access. `CriticalAlertAudioPlayer`
    /// is `@MainActor` (its `MPVolumeView` + `Timer` members require main),
    /// but `BaseTrioAlertManager.init` runs on the Swinject resolve thread.
    @MainActor private var criticalAudioPlayer: CriticalAlertAudioPlayer?

    let modalScheduler: TrioModalAlertScheduler
    private let userNotificationScheduler: TrioUserNotificationAlertScheduler

    private let queue = DispatchQueue(label: "BaseTrioAlertManager.queue")
    private var responders: [String: WeakRef] = [:]
    private var soundVendors: [String: WeakRef] = [:]
    private var liveAlerts: [Alert.Identifier: Alert] = [:]

    init(resolver: Resolver) {
        muter = AlertMuter()
        throttler = AlertThrottler()
        let soundsRoot = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .last!
            .appendingPathComponent(Self.soundsDirectoryName, isDirectory: true)
        soundLoader = AlertSoundLoader(destination: soundsRoot)
        modalScheduler = TrioModalAlertScheduler()
        userNotificationScheduler = TrioUserNotificationAlertScheduler(
            notificationCenter: UNUserNotificationCenter.current(),
            soundsRoot: soundsRoot
        )
        injectServices(resolver)
        modalScheduler.responder = self
        userNotificationScheduler.responder = self
        // Rehydrate the in-memory mute window from the persisted snoozeUntilDate
        // so a force-quit + relaunch during an active snooze still suppresses
        // non-critical alerts until the originally-chosen end time.
        let persistedSnoozeUntil = UserDefaults.standard
            .object(forKey: "UserNotificationsManager.snoozeUntilDate") as? Date
        if let until = persistedSnoozeUntil, until > Date() {
            muter.mute(for: until.timeIntervalSinceNow)
        }
    }

    /// Falls back to in-process AVAudioPlayer for `.critical` alerts on
    /// builds without the Critical Alerts entitlement. iOS silently
    /// downgrades `.criticalSoundNamed` and `.defaultCritical` to a regular
    /// notification without the entitlement, which DnD / silent switch /
    /// Focus modes then mute — dangerous for an overnight urgent-low.
    /// `.playback` audio session bypasses those.
    ///
    /// Only fires for immediate-trigger alerts; delayed/repeating go
    /// through UNNotification at fire time. No-op when muted or non-critical.
    private func playCriticalAudioFallbackIfNeeded(_ alert: Alert, muted: Bool) {
        guard alert.interruptionLevel == .critical, !muted else { return }
        guard case .immediate = alert.trigger else { return }
        // Honor `playsSound: false` (alert was issued with sound: nil) —
        // user explicitly opted out of audio on this alarm.
        guard let soundName = alert.sound?.filename else { return }
        Task { @MainActor in
            if criticalAudioPlayer == nil { criticalAudioPlayer = CriticalAlertAudioPlayer() }
            criticalAudioPlayer?.play(soundNamed: soundName)
        }
    }

    // MARK: - Issue / Retract

    func issueAlert(_ alert: Alert) {
        debug(
            .service,
            "TrioAlertManager.issueAlert \(alert.identifier.value) level=\(alert.interruptionLevel)"
        )

        // Pump alerts: look up in catalog → override interruptionLevel.
        // Everything else (CGM lifecycle, Trio-internal glucose / loop) is
        // passed through with the level its producer chose.
        let effective: Alert = AlertCatalogRegistry.lookup(alert.identifier).map { entry in
            applyCatalogEntry(entry, to: alert)
        } ?? alert

        // Per-tier snooze for catalog-known pump alerts. Critical tier
        // ignores snooze.
        if let tier = DeviceAlertSeverity(level: effective.interruptionLevel),
           AlertCatalogRegistry.lookup(effective.identifier) != nil,
           tier != .critical,
           DeviceAlertsStore.shared.isTierSnoozed(tier, at: Date())
        {
            debug(.service, "TrioAlertManager dropped \(effective.identifier.value): tier \(tier) snoozed")
            return
        }

        let now = Date()
        // Critical alerts pierce the snooze/mute window. Everything else is
        // suppressed entirely while muted (no modal, no UN sound, no critical
        // audio fallback).
        if effective.interruptionLevel != .critical, muter.shouldMute(at: now) {
            debug(.service, "TrioAlertManager muted \(effective.identifier.value) (snooze window active)")
            return
        }
        guard throttler.shouldDeliver(effective) else {
            debug(.service, "TrioAlertManager throttled \(effective.identifier.value)")
            return
        }
        queue.async {
            self.liveAlerts[effective.identifier] = effective
        }
        recordIssued(effective)
        let muted = muter.shouldMute(at: now)
        modalScheduler.schedule(effective)
        userNotificationScheduler.schedule(
            effective,
            muted: muted,
            soundURL: soundLoader.url(for: effective)
        )
        playCriticalAudioFallbackIfNeeded(effective, muted: muted)
    }

    private func applyCatalogEntry(_ entry: Alert.CatalogEntry, to alert: Alert) -> Alert {
        Alert(
            identifier: alert.identifier,
            foregroundContent: alert.foregroundContent,
            backgroundContent: alert.backgroundContent,
            trigger: alert.trigger,
            interruptionLevel: entry.interruptionLevel,
            sound: alert.sound,
            metadata: alert.metadata
        )
    }

    func retractAlert(identifier: Alert.Identifier) {
        queue.async {
            self.liveAlerts.removeValue(forKey: identifier)
        }
        modalScheduler.unschedule(identifier: identifier)
        userNotificationScheduler.unschedule(identifier: identifier)
        throttler.reset(identifier: identifier)
        Task { @MainActor in criticalAudioPlayer?.stop() }
        alertHistoryStorage.removeAlert(identifier: identifier.alertIdentifier)
    }

    // MARK: - Acknowledgement

    func handleAcknowledgement(identifier: Alert.Identifier) {
        modalScheduler.unschedule(identifier: identifier)
        userNotificationScheduler.unschedule(identifier: identifier)
        Task { @MainActor in criticalAudioPlayer?.stop() }
        alertHistoryStorage.acknowledgeAlert(issuedDate(for: identifier) ?? Date(), nil)
        queue.async {
            self.liveAlerts.removeValue(forKey: identifier)
        }
        let responder = queue.sync { responders[identifier.managerIdentifier]?.ref as? AlertResponder }
        responder?.acknowledgeAlert(alertIdentifier: identifier.alertIdentifier) { error in
            if let error = error {
                debug(.service, "AlertManager ack failed for \(identifier.value): \(error)")
            }
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        guard
            let managerId = userInfo[AlertUserInfoKey.managerIdentifier.rawValue] as? String,
            let alertId = userInfo[AlertUserInfoKey.alertIdentifier.rawValue] as? String
        else { return }
        let identifier = Alert.Identifier(managerIdentifier: managerId, alertIdentifier: alertId)
        handleAcknowledgement(identifier: identifier)
    }

    func acknowledgeAllOutstanding() {
        let outstanding = alertHistoryStorage.unacknowledgedAlertsWithinLast24Hours()
        for entry in outstanding {
            let identifier = Alert.Identifier(
                managerIdentifier: entry.managerIdentifier,
                alertIdentifier: entry.alertIdentifier
            )
            handleAcknowledgement(identifier: identifier)
        }
    }

    func clearPendingNonCriticalNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.content.interruptionLevel != .critical }
                .map(\.identifier)
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { $0.request.content.interruptionLevel != .critical }
                .map(\.request.identifier)
            guard !ids.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Persisted under the same key UN reads, so a force-quit + relaunch
    /// during a snooze sees the same end-date.
    private static let snoozeUntilDateKey = "UserNotificationsManager.snoozeUntilDate"
    private static let legacyGlucoseNotificationID = "Trio.glucoseNotification"

    @MainActor func applySnooze(for duration: TimeInterval) async {
        let untilDate = duration > 0 ? Date().addingTimeInterval(duration) : .distantPast
        UserDefaults.standard.set(untilDate, forKey: Self.snoozeUntilDateKey)

        // Legacy glucose-notification UN cleanup (the new pipeline uses
        // per-alarm identifiers; this catches anything still lingering
        // from older installs).
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.legacyGlucoseNotificationID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.legacyGlucoseNotificationID])

        if duration > 0 {
            muter.mute(for: duration)
            clearPendingNonCriticalNotifications()
            modalScheduler.clearNonCriticalBanners()
        } else {
            muter.unmute()
        }

        broadcaster.notify(SnoozeObserver.self, on: .main) { (observer: SnoozeObserver) in
            observer.snoozeDidChange(untilDate)
        }
    }

    // MARK: - Registry

    func register(responder: AlertResponder, for managerIdentifier: String) {
        queue.async {
            self.responders[managerIdentifier] = WeakRef(ref: responder as AnyObject)
        }
    }

    func register(soundVendor: AlertSoundVendor, for managerIdentifier: String) {
        queue.async {
            self.soundVendors[managerIdentifier] = WeakRef(ref: soundVendor as AnyObject)
        }
        soundLoader.copySounds(from: soundVendor, managerIdentifier: managerIdentifier)
    }

    func unregister(managerIdentifier: String) {
        queue.async {
            self.responders.removeValue(forKey: managerIdentifier)
            self.soundVendors.removeValue(forKey: managerIdentifier)
        }
    }

    func soundURL(for alert: Alert) -> URL? {
        soundLoader.url(for: alert)
    }

    // MARK: - Persistence bridge

    private func recordIssued(_ alert: Alert) {
        let entry = AlertEntry(
            alertIdentifier: alert.identifier.alertIdentifier,
            primitiveInterruptionLevel: alert.interruptionLevel.storedValue as? Decimal,
            issuedDate: Date(),
            managerIdentifier: alert.identifier.managerIdentifier,
            triggerType: alert.trigger.storedType,
            triggerInterval: alert.trigger.storedInterval as? Decimal,
            contentTitle: alert.foregroundContent?.title ?? alert.backgroundContent.title,
            contentBody: alert.foregroundContent?.body ?? alert.backgroundContent.body
        )
        alertHistoryStorage.addAlert(entry)
    }

    private func issuedDate(for identifier: Alert.Identifier) -> Date? {
        alertHistoryStorage.unacknowledgedAlertsWithinLast24Hours()
            .first {
                $0.managerIdentifier == identifier.managerIdentifier
                    && $0.alertIdentifier == identifier.alertIdentifier
            }?.issuedDate
    }
}

extension BaseTrioAlertManager: TrioModalAlertResponder, TrioUserNotificationAlertResponder {
    func requestSnooze(identifier: Alert.Identifier, duration: TimeInterval) {
        let untilDate = duration > 0 ? Date().addingTimeInterval(duration) : .distantPast
        if let glucoseType = GlucoseAlertType(slug: identifier.alertIdentifier) {
            broadcaster.notify(GlucoseSnoozeObserver.self, on: .main) { (observer: GlucoseSnoozeObserver) in
                observer.snoozeGlucoseType(glucoseType, until: untilDate)
            }
        } else if let entry = AlertCatalogRegistry.lookup(identifier),
                  let tier = DeviceAlertSeverity(level: entry.interruptionLevel),
                  tier != .critical
        {
            DeviceAlertsStore.shared.snoozeTier(tier, until: untilDate)
            retractAlertsInTier(tier)
        } else {
            Task { @MainActor [weak self] in
                await self?.applySnooze(for: duration)
            }
        }
    }

    private func retractAlertsInTier(_ tier: DeviceAlertSeverity) {
        let toRetract: [Alert.Identifier] = queue.sync {
            liveAlerts.compactMap { id, alert in
                guard let entry = AlertCatalogRegistry.lookup(id),
                      DeviceAlertSeverity(level: entry.interruptionLevel) == tier
                else { return nil }
                _ = alert
                return id
            }
        }
        for id in toRetract {
            retractAlert(identifier: id)
        }
    }

    /// Convenience for the UN-action / Watch / Snooze-module paths that
    /// don't have an originating alert identifier — they all want global.
    func requestSnooze(duration: TimeInterval) {
        Task { @MainActor [weak self] in
            await self?.applySnooze(for: duration)
        }
    }

    func isAlertActive(identifier: Alert.Identifier) -> Bool {
        queue.sync { liveAlerts[identifier] != nil }
    }

    func isSnoozeActive(at date: Date) -> Bool {
        muter.shouldMute(at: date)
    }
}

/// Observer for per-type glucose snoozes triggered from an in-app banner.
/// `GlucoseAlertCoordinator` registers and applies the snooze to its
/// `snoozedUntil` field on every matching `GlucoseAlert`.
protocol GlucoseSnoozeObserver {
    func snoozeGlucoseType(_ type: GlucoseAlertType, until: Date)
}

enum AlertUserInfoKey: String {
    case managerIdentifier = "trio.alert.managerIdentifier"
    case alertIdentifier = "trio.alert.alertIdentifier"
}

// MARK: - Muter

final class AlertMuter: ObservableObject {
    @Published private(set) var startDate: Date?
    @Published private(set) var duration: TimeInterval = 0

    static let allowedDurations: [TimeInterval] = [
        30 * 60,
        60 * 60,
        2 * 60 * 60,
        4 * 60 * 60
    ]

    func mute(for duration: TimeInterval, from start: Date = Date()) {
        startDate = start
        self.duration = duration
    }

    func unmute() {
        startDate = nil
        duration = 0
    }

    func shouldMute(at date: Date) -> Bool {
        guard let start = startDate else { return false }
        return date >= start && date < start.addingTimeInterval(duration)
    }

    var endsAt: Date? {
        guard let start = startDate else { return nil }
        return start.addingTimeInterval(duration)
    }
}

// MARK: - Throttler

final class AlertThrottler {
    private let queue = DispatchQueue(label: "AlertThrottler.queue")
    private var lastDelivered: [Alert.Identifier: Date] = [:]
    private let minimumInterval: TimeInterval = 5 * 60

    func shouldDeliver(_ alert: Alert) -> Bool {
        queue.sync {
            let now = Date()
            if let last = lastDelivered[alert.identifier], now.timeIntervalSince(last) < minimumInterval {
                return false
            }
            lastDelivered[alert.identifier] = now
            return true
        }
    }

    func reset(identifier: Alert.Identifier) {
        queue.sync { _ = lastDelivered.removeValue(forKey: identifier) }
    }
}

// MARK: - Sound loader

final class AlertSoundLoader {
    private let destination: URL
    private let fileManager: FileManager

    init(destination: URL, fileManager: FileManager = .default) {
        self.destination = destination
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    func copySounds(from vendor: AlertSoundVendor, managerIdentifier: String) {
        guard let sourceBase = vendor.getSoundBaseURL() else { return }
        let target = destination.appendingPathComponent(managerIdentifier, isDirectory: true)
        try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for sound in vendor.getSounds() {
            guard let filename = sound.filename else { continue }
            let source = sourceBase.appendingPathComponent(filename)
            let dest = target.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            if fileManager.fileExists(atPath: dest.path) { continue }
            try? fileManager.copyItem(at: source, to: dest)
        }
    }

    func url(for alert: Alert) -> URL? {
        guard let filename = alert.sound?.filename else { return nil }
        let url = destination
            .appendingPathComponent(alert.identifier.managerIdentifier, isDirectory: true)
            .appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
