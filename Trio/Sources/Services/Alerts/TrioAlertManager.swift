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
        let category = TrioAlertClassifier.categorize(alertIdentifier: alert.identifier.alertIdentifier)
        debug(
            .service,
            "TrioAlertManager.issueAlert \(alert.identifier.value) category=\(category) level=\(alert.interruptionLevel)"
        )
        guard category.isAlertWorthy else {
            debug(.service, "TrioAlertManager dropped \(alert.identifier.value): \(category) not alert-worthy")
            return
        }

        // Apply the user's tier config for pump / device alarms. The category
        // maps to one of three tiers (Critical / Time-Sensitive / Normal) and
        // the tier config overrides sound + interruption level. Glucose
        // alarms bypass this — they're owned by `GlucoseAlertCoordinator`.
        let effective: Alert
        if let pumpCategory = PumpAlertCategory(trioCategory: category) {
            effective = applyDeviceSeverityConfig(to: alert, category: pumpCategory)
        } else {
            effective = alert
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

    private func applyDeviceSeverityConfig(to alert: Alert, category: PumpAlertCategory) -> Alert {
        let severity = category.defaultSeverity
        guard let config = DeviceAlertsStore.shared.config(for: severity) else { return alert }
        let sound: Alert.Sound? = config.playsSound ? .sound(name: config.soundFilename) : nil
        let level: Alert.InterruptionLevel = config.overridesSilenceAndDND ? .critical : .timeSensitive
        return Alert(
            identifier: alert.identifier,
            foregroundContent: alert.foregroundContent,
            backgroundContent: alert.backgroundContent,
            trigger: alert.trigger,
            interruptionLevel: level,
            sound: sound,
            metadata: alert.metadata
        )
    }

    func retractAlert(identifier: Alert.Identifier) {
        queue.async {
            self.liveAlerts.removeValue(forKey: identifier)
        }
        modalScheduler.unschedule(identifier: identifier)
        userNotificationScheduler.unschedule(identifier: identifier)
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

extension BaseTrioAlertManager: TrioModalAlertResponder, TrioUserNotificationAlertResponder {}

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
