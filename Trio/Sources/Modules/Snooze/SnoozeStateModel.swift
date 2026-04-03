import Observation
import SwiftUI

extension Snooze {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var notificationsManager: UserNotificationsManager!
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!

        var alarm: GlucoseAlarm?

        override func subscribe() {
            alarm = glucoseStorage.alarm
            broadcaster.register(SnoozeObserver.self, observer: self)
        }

        func unsubscribe() {
            broadcaster.unregister(SnoozeObserver.self, observer: self)
        }

        // Add validation helper inside the class
        private func validateSnoozeDuration(_ duration: TimeInterval) -> Bool {
            // Only allow durations matching our defined actions
            NotificationResponseAction.allCases
                .map(\.duration)
                .contains(duration)
        }

        @MainActor func applySnooze(_ duration: TimeInterval) async {
            // Allow any duration chosen in the Snooze UI, while keeping validation for quick actions elsewhere.
            snoozeUntilDate = duration > 0 ? Date().addingTimeInterval(duration) : .distantPast
            alarm = glucoseStorage.alarm
            await notificationsManager.applySnooze(for: duration)
        }
    }
}

extension Snooze.StateModel: SnoozeObserver {
    func snoozeDidChange(_ untilDate: Date) {
        snoozeUntilDate = untilDate
        alarm = glucoseStorage.alarm
    }
}
