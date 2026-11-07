import Foundation
import UserNotifications
import WatchKit

/// The phone's glucose alarms, sounded on the watch for its own readings: only while the phone's readings have stopped
/// coming (`WatchState.phoneReadingsAreFresh`), since the phone alarms on every reading it has. Thresholds are the
/// phone's alarms (`WatchGlucoseRange`).
@MainActor final class WatchAlarms {
    static let shared = WatchAlarms()

    /// Every watch notification's identifier starts with it, so they show with Trio open on the wrist too.
    static let notificationPrefix = "trio.watch."
    /// Safety alarms that bypass Silent Mode when Critical Alerts are on.
    static let criticalKinds: Set<String> = ["urgentLow"]

    private var lastAlarm: [String: Date] = [:]

    func check(own readings: [BloodGlucose], now: Date = Date()) {
        let state = WatchState.shared
        let phoneNewest = state.phoneNewestReading ?? .distantPast
        guard !state.phoneReadingsAreFresh(at: now),
              let latest = readings.max(by: { $0.dateString < $1.dateString }),
              latest.dateString > phoneNewest.addingTimeInterval(60),
              now.timeIntervalSince(latest.dateString) < 12 * 60,
              let value = latest.glucose ?? latest.sgv
        else { return }
        let range = state.glucoseRange
        let mgdl = Decimal(value)
        let formatted = range.isMmol ? "\(mgdl.formatted(for: .mmolL)) mmol/L" : "\(value) mg/dL"
        let body = [formatted, Self.arrow(latest.direction)].filter { !$0.isEmpty }.joined(separator: " ")
        if mgdl <= range.urgentLowAlarm {
            alarm("urgentLow", title: String(localized: "Urgent Low"), body: body, every: 5 * 60)
        } else if mgdl <= range.lowAlarm ?? range.low {
            alarm("low", title: String(localized: "Low Glucose"), body: body, every: 15 * 60)
        } else if mgdl >= range.highAlarm ?? range.high {
            alarm("high", title: String(localized: "High Glucose"), body: body, every: 60 * 60)
        }
    }

    static func arrow(_ direction: BloodGlucose.Direction?) -> String {
        switch direction {
        case .doubleUp: return "⇈"
        case .singleUp: return "↑"
        case .fortyFiveUp: return "↗"
        case .flat: return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown: return "↓"
        case .doubleDown: return "⇊"
        default: return ""
        }
    }

    private func alarm(_ kind: String, title: String, body: String, every interval: TimeInterval) {
        guard (lastAlarm[kind] ?? .distantPast).addingTimeInterval(interval) < Date() else { return }
        // as on the phone: a snooze (set on either) silences all but urgent low
        let snoozedUntil = WatchState.shared.snoozeUntilDate
        guard kind == "urgentLow" || snoozedUntil <= Date() else {
            WatchLogger.shared.info(.data, "Watch alarm snoozed until \(snoozedUntil): \(title)")
            return
        }
        lastAlarm[kind] = Date()
        notify(id: Self.notificationPrefix + kind, critical: Self.criticalKinds.contains(kind), title: title, body: body)
        // felt at once while the app runs; the notification may wait for the screen
        WKInterfaceDevice.current().play(kind == "high" ? .notification : .failure)
        WatchLogger.shared.info(.data, "Watch alarm: \(title) \(body)")
    }

    func notify(id: String, critical: Bool = false, title: String, body: String, after delay: TimeInterval? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = critical && WatchState.shared.useCriticalAlerts ? .defaultCritical : .default
        // the phone's snooze actions
        content.categoryIdentifier = NotificationCategoryIdentifier.trioAlert.rawValue
        let trigger = delay.flatMap { $0 > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) : nil }
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                if let error { WatchLogger.shared.warning(.data, "Notification \(id) failed", error: error) }
            }
    }
}
