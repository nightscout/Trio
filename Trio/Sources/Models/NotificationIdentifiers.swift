import Foundation

enum NotificationCategoryIdentifier: String {
    case glucoseAlert = "Trio.glucoseAlert"
}

enum NotificationResponseAction: String, CaseIterable {
    case snooze20 = "Trio.snooze20"
    case snooze1hr = "Trio.snooze1hr"
    case snooze3hr = "Trio.snooze3hr"
    case snooze6hr = "Trio.snooze6hr"

    var duration: TimeInterval {
        TimeInterval(minutes * 60)
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
}
