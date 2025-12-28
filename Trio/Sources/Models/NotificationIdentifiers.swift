import Foundation

enum NotificationCategoryIdentifier: String {
    case glucoseAlert = "Trio.glucoseAlert"
}

enum NotificationResponseAction: String, CaseIterable {
    case snooze20 = "Trio.snooze20"
    case snooze40 = "Trio.snooze40"
    case snooze60 = "Trio.snooze60"

    var duration: TimeInterval {
        TimeInterval(minutes * 60)
    }

    var minutes: Int {
        switch self {
        case .snooze20:
            return 20
        case .snooze40:
            return 40
        case .snooze60:
            return 60
        }
    }
}
