import Foundation
import LoopKit
import os.log

#if canImport(AlarmKit)
    import ActivityKit
    import AlarmKit
    import AppIntents
    import struct SwiftUI.Color // Color only; `import SwiftUI` makes `Alert` ambiguous with LoopKit.Alert
#endif

/// On iOS 26+ this schedules an AlarmKit alarm as the audible critical-alert
/// channel instead of the AVAudioSession + volume-booster + vibration hack in
/// `CriticalAlertAudioPlayer`. AlarmKit breaks through the silent switch,
/// Focus and Do Not Disturb with a system-rendered alarm, and — unlike the
/// in-process player — still fires when iOS has suspended Trio.
///
/// Requires the user to grant AlarmKit authorization. When AlarmKit is
/// unavailable (iOS < 26) or unauthorized, callers fall back to
/// `CriticalAlertAudioPlayer`.
///
/// Ported from Loop's `CriticalAlertAlarmScheduler`.
@MainActor
final class CriticalAlertAlarmScheduler {
    private let log = OSLog(subsystem: "org.nightscout.trio", category: "CriticalAlertAlarmScheduler")

    /// Maps an issued alert to the AlarmKit alarm scheduled for it, so the
    /// alarm can be cancelled when the alert is acknowledged or retracted.
    private var alarmsByAlert: [Alert.Identifier: UUID] = [:]

    /// True only if AlarmKit is available (iOS 26+) AND the user authorized it.
    /// When false, callers should use the `CriticalAlertAudioPlayer` fallback.
    var isAuthorizedAndAvailable: Bool {
        guard #available(iOS 26, *) else { return false }
        #if canImport(AlarmKit)
            return AlarmManager.shared.authorizationState == .authorized
        #else
            return false
        #endif
    }

    /// Request AlarmKit authorization if it hasn't been decided yet. No-op
    /// below iOS 26 or once already granted/denied.
    static func requestAuthorization() async {
        guard #available(iOS 26, *) else { return }
        #if canImport(AlarmKit)
            guard AlarmManager.shared.authorizationState == .notDetermined else { return }
            do {
                _ = try await AlarmManager.shared.requestAuthorization()
            } catch {
                os_log(
                    "AlarmKit authorization request failed: %{public}@",
                    log: OSLog(subsystem: "org.nightscout.trio", category: "CriticalAlertAlarmScheduler"),
                    type: .error,
                    String(describing: error)
                )
            }
        #endif
    }

    /// AlarmKit fixed alarms ring at a future wall-clock moment; a now/past
    /// date schedules silently and never fires, so nudge it a couple seconds ahead.
    private static let immediateFireDelay: TimeInterval = 2

    /// Schedule an (effectively immediate) AlarmKit alarm for the alert.
    /// Returns true if AlarmKit will handle it, so the caller skips the audio
    /// fallback. `onScheduleFailure` runs if the async schedule throws, so the
    /// caller can still play the fallback rather than leaving the alert silent.
    @discardableResult func scheduleAlarm(for alert: Alert, onScheduleFailure: @escaping () -> Void) -> Bool {
        guard #available(iOS 26, *), isAuthorizedAndAvailable else { return false }
        #if canImport(AlarmKit)
            cancelAlarm(for: alert.identifier)

            let stopButton = AlarmButton(
                text: LocalizedStringResource(stringLiteral: String(localized: "Stop")),
                textColor: .white,
                systemImageName: "stop.circle"
            )
            let presentation = AlarmPresentation(
                alert: AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: alert.backgroundContent.title),
                    stopButton: stopButton
                )
            )
            let attributes = AlarmAttributes<EmptyAlarmMetadata>(presentation: presentation, tintColor: .red)

            // Alert-only (no countdownDuration) so no Widget Extension / Live
            // Activity is required. `AlertSound.named` resolves the same way
            // `UNNotificationSoundName` does — main bundle root or
            // Library/Sounds — which is where Trio's tones now live.
            let sound: AlertConfiguration.AlertSound = alert.sound?.filename
                .map { .named($0) } ?? .default
            let configuration = AlarmManager.AlarmConfiguration<EmptyAlarmMetadata>.alarm(
                schedule: .fixed(Date().addingTimeInterval(Self.immediateFireDelay)),
                attributes: attributes,
                stopIntent: StopCriticalAlertIntent(identifier: alert.identifier),
                sound: sound
            )

            let id = UUID()
            alarmsByAlert[alert.identifier] = id
            let log = self.log
            let identifier = alert.identifier
            Task { [weak self] in
                do {
                    _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                    os_log(
                        "Scheduled AlarmKit alarm %{public}@ for %{public}@",
                        log: log, type: .info, id.uuidString, identifier.value
                    )
                } catch {
                    os_log(
                        "Failed to schedule AlarmKit alarm for %{public}@: %{public}@ — falling back to audio",
                        log: log, type: .error, identifier.value, String(describing: error)
                    )
                    self?.alarmsByAlert.removeValue(forKey: identifier)
                    onScheduleFailure()
                }
            }
            return true
        #else
            return false
        #endif
    }

    /// Cancel/stop the AlarmKit alarm scheduled for the given alert, if any.
    func cancelAlarm(for identifier: Alert.Identifier) {
        guard #available(iOS 26, *) else { return }
        #if canImport(AlarmKit)
            guard let id = alarmsByAlert.removeValue(forKey: identifier) else { return }
            // The alarm may be ringing or merely scheduled; try both and ignore errors.
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
            os_log(
                "Cancelled AlarmKit alarm %{public}@ for %{public}@",
                log: log, type: .info, id.uuidString, identifier.value
            )
        #endif
    }
}

/// Hands the AlarmKit Stop button's tap back to the alert manager so the
/// corresponding Trio alert is acknowledged, not just silenced. The intent is
/// reconstructed by the system and has no reference to the live manager, so it
/// routes through this shared bridge. Taps that arrive before the manager
/// registers (e.g. the app was relaunched to run the intent) are queued and
/// flushed once it does.
@MainActor final class CriticalAlertAcknowledgementBridge {
    static let shared = CriticalAlertAcknowledgementBridge()
    private init() {}

    private var handler: ((Alert.Identifier) async -> Void)?
    private var pending: [Alert.Identifier] = []

    func setHandler(_ handler: @escaping (Alert.Identifier) async -> Void) {
        self.handler = handler
        guard !pending.isEmpty else { return }
        let queued = pending
        pending = []
        Task { for identifier in queued { await handler(identifier) } }
    }

    func acknowledge(_ identifier: Alert.Identifier) async {
        if let handler {
            await handler(identifier)
        } else {
            pending.append(identifier)
        }
    }
}

#if canImport(AlarmKit)
    /// Trio critical-alert alarms are alert-only (no countdown / custom Live
    /// Activity), so this carries nothing.
    @available(iOS 26, *) struct EmptyAlarmMetadata: AlarmMetadata {
        init() {}
    }

    /// Runs in the app process when the user taps Stop on an AlarmKit critical
    /// alarm. Carries the alert identifier as parameters so the system can
    /// reconstruct it.
    @available(iOS 26, *) struct StopCriticalAlertIntent: LiveActivityIntent {
        static var title: LocalizedStringResource = "Stop Trio Alarm"
        static var isDiscoverable: Bool = false

        @Parameter(title: "Manager Identifier") var managerIdentifier: String
        @Parameter(title: "Alert Identifier") var alertIdentifier: String

        init() {}

        init(identifier: Alert.Identifier) {
            managerIdentifier = identifier.managerIdentifier
            alertIdentifier = identifier.alertIdentifier
        }

        func perform() async throws -> some IntentResult {
            await CriticalAlertAcknowledgementBridge.shared.acknowledge(
                Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier)
            )
            return .result()
        }
    }
#endif
