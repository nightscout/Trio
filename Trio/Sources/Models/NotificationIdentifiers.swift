import Foundation
import UserNotifications

enum NotificationCategoryIdentifier: String {
    case trioAlert = "Trio.alert"
}

enum NotificationResponseAction: String, CaseIterable {
    case snooze20 = "Trio.snooze20"
    case snooze1hr = "Trio.snooze1hr"
    case snooze3hr = "Trio.snooze3hr"
    case snooze6hr = "Trio.snooze6hr"

    var duration: TimeInterval {
        TimeInterval(minutes) * 60
    }

    var minutes: Int {
        switch self {
        case .snooze20:
            return 20
        case .snooze1hr:
            return 60
        case .snooze3hr:
            return 180
        case .snooze6hr:
            return 360
        }
    }

    var localizedTitle: String {
        switch self {
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
}

// MARK: - NotificationCategoryFactory

enum NotificationCategoryFactory {
    static func createGlucoseCategory() -> UNNotificationCategory {
        let snoozeActions = NotificationResponseAction.allCases.map { action in
            UNNotificationAction(
                identifier: action.rawValue,
                title: action.localizedTitle,
                options: []
            )
        }

        return UNNotificationCategory(
            identifier: NotificationCategoryIdentifier.trioAlert.rawValue,
            actions: snoozeActions,
            intentIdentifiers: [],
            options: []
        )
    }
}
