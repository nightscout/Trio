import Foundation
import UserNotifications
import WatchConnectivity

final class WatchNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationHandler()

    private override init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories(on: center)
    }

    private func registerCategories(on center: UNUserNotificationCenter) {
        center.getNotificationCategories { existingCategories in
            let snoozeActions = NotificationResponseAction.allCases.map { action in
                UNNotificationAction(
                    identifier: action.rawValue,
                    title: self.title(for: action),
                    options: []
                )
            }

            let glucoseCategory = UNNotificationCategory(
                identifier: NotificationCategoryIdentifier.glucoseAlert.rawValue,
                actions: snoozeActions,
                intentIdentifiers: [],
                options: []
            )

            var categories = existingCategories
            categories.update(with: glucoseCategory)
            center.setNotificationCategories(categories)
        }
    }

    private func title(for action: NotificationResponseAction) -> String {
        switch action {
        case .snooze20:
            return String(localized: "20 min", comment: "Snooze glucose alerts for 20 minutes")
        case .snooze1hr:
            return String(localized: "1 hour", comment: "Snooze glucose alerts for 1 hour")
        case .snooze3hr:
            return String(localized: "3 hours", comment: "Snooze glucose alerts for 3 hours")
        case .snooze6hr:
            return String(localized: "6 hours", comment: "Snooze glucose alerts for 6 hours")
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let action = NotificationResponseAction(rawValue: response.actionIdentifier) else { return }
        sendSnoozeRequest(for: action)
    }

    private func sendSnoozeRequest(for action: NotificationResponseAction) {
        guard WCSession.isSupported() else { return }

        let payload: [String: Any] = [WatchMessageKeys.snoozeDuration: action.minutes]
        let session = WCSession.default

        if session.delegate == nil {
            session.delegate = PassiveSessionDelegate.shared
        }

        if session.activationState == .notActivated {
            session.activate()
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
}

private final class PassiveSessionDelegate: NSObject, WCSessionDelegate {
    static let shared = PassiveSessionDelegate()

    private override init() {}

    func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {}

#if os(watchOS)
    func sessionReachabilityDidChange(_: WCSession) {}
#endif
}
