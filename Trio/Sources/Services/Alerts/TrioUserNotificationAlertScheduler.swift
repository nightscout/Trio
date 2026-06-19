import Foundation
import LoopKit
import UserNotifications

protocol TrioUserNotificationAlertResponder: AnyObject {
    func handleAcknowledgement(identifier: Alert.Identifier)
}

final class TrioUserNotificationAlertScheduler {
    weak var responder: TrioUserNotificationAlertResponder?

    private let notificationCenter: UNUserNotificationCenter
    private let soundsRoot: URL

    init(notificationCenter: UNUserNotificationCenter, soundsRoot: URL) {
        self.notificationCenter = notificationCenter
        self.soundsRoot = soundsRoot
    }

    func schedule(_ alert: Alert, muted: Bool, soundURL: URL?) {
        let request = makeRequest(alert: alert, muted: muted, soundURL: soundURL)
        notificationCenter.add(request) { error in
            if let error = error {
                debug(.service, "UserNotificationAlertScheduler failed: \(error.localizedDescription)")
            }
        }
    }

    func unschedule(identifier: Alert.Identifier) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.value])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
    }

    private func makeRequest(alert: Alert, muted: Bool, soundURL: URL?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.backgroundContent.title
        content.body = alert.backgroundContent.body
        content.threadIdentifier = alert.identifier.managerIdentifier
        content.userInfo = [
            AlertUserInfoKey.managerIdentifier.rawValue: alert.identifier.managerIdentifier,
            AlertUserInfoKey.alertIdentifier.rawValue: alert.identifier.alertIdentifier
        ]
        content.interruptionLevel = alert.interruptionLevel.unNotificationLevel
        content.sound = sound(for: alert, muted: muted, soundURL: soundURL)
        // Surface the four quick-snooze actions (20 min / 1 h / 3 h / 6 h)
        // on both phone and watch lock-screen notifications. The category +
        // its actions are registered by `NotificationCategoryFactory` on
        // both the phone (`BaseUserNotificationsManager`) and watch
        // (`WatchNotificationHandler`) UN delegates.
        content.categoryIdentifier = NotificationCategoryIdentifier.trioAlert.rawValue

        return UNNotificationRequest(
            identifier: alert.identifier.value,
            content: content,
            trigger: alert.trigger.unTrigger
        )
    }

    private func sound(for alert: Alert, muted: Bool, soundURL: URL?) -> UNNotificationSound? {
        let isCritical = alert.interruptionLevel == .critical
        if muted {
            return isCritical ? .defaultCriticalSound(withAudioVolume: 0) : nil
        }
        switch alert.sound {
        case .none,
             .vibrate:
            return isCritical ? .defaultCriticalSound(withAudioVolume: 0) : nil
        case let .sound(name):
            if let filename = soundURL?.lastPathComponent {
                let unName = UNNotificationSoundName(rawValue: filename)
                return isCritical ? .criticalSoundNamed(unName) : UNNotificationSound(named: unName)
            }
            let unName = UNNotificationSoundName(name)
            return isCritical ? .criticalSoundNamed(unName) : UNNotificationSound(named: unName)
        }
    }
}

private extension Alert.InterruptionLevel {
    var unNotificationLevel: UNNotificationInterruptionLevel {
        switch self {
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        case .critical: return .critical
        }
    }
}

private extension Alert.Trigger {
    var unTrigger: UNNotificationTrigger? {
        switch self {
        case .immediate:
            return nil
        case let .delayed(interval):
            return UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        case let .repeating(interval):
            return UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 60), repeats: true)
        }
    }
}
