import Foundation
import UserNotifications

private var logger = DanaLogger(category: "NotificationHelper")

public enum NotificationHelper {
    private enum Identifiers: String {
        case disconnectedReminder = "com.bastiaanv.continuous-ble.disconnect-reminder"
        case disconnectWarning = "com.bastiaanv.continuous-ble.disconnect-warning"
    }

    public static func setDisconnectReminder(_ after: TimeInterval) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Pump is still disconnected", comment: "Title disconnect reminder notification")
            content.body = LocalizedString(
                "Your pump is still disconnected after the set period!",
                comment: "Body disconnect reminder notification"
            )

            addRequest(identifier: .disconnectedReminder, content: content, triggerAfter: after)
        }
    }

    public static func clearDisconnectReminder() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Identifiers.disconnectedReminder.rawValue])
        center.removePendingNotificationRequests(withIdentifiers: [Identifiers.disconnectedReminder.rawValue])
    }

    public static func setDisconnectWarning() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Pump is disconnected", comment: "Title disconnect warning notification")
            content.body = LocalizedString(
                "Your pump is disconnected longer than 5 minutes!",
                comment: "Body disconnect warning notification"
            )

            addRequest(identifier: .disconnectWarning, content: content, triggerAfter: .minutes(5))
        }
    }

    public static func clearDisconnectWarning() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Identifiers.disconnectWarning.rawValue])
        center.removePendingNotificationRequests(withIdentifiers: [Identifiers.disconnectWarning.rawValue])
    }

    private static func addRequest(
        identifier: Identifiers,
        content: UNMutableNotificationContent,
        triggerAfter: TimeInterval? = nil,
        deleteOld: Bool = false
    ) {
        let center = UNUserNotificationCenter.current()
        var trigger: UNCalendarNotificationTrigger?

        if deleteOld {
            // Required since ios12+ have started to cache/group notifications
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        if let triggerAfter = triggerAfter {
            let notifTime = Date.now.addingTimeInterval(triggerAfter)
            let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: notifTime)

            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        }

        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                logger.info("unable to addNotificationRequest: \(error.localizedDescription)")
                return
            }

            logger.info("sending \(identifier.rawValue) notification")
        }
    }

    private static func ensureCanSendNotification(_ completion: @escaping () -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                logger.info("ensureCanSendNotification failed, authorization denied")
                return
            }

            logger.info("sending notification was allowed")

            completion()
        }
    }
}
