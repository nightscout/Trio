import Observation
import SwiftUI

extension Snooze {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast
        @ObservationIgnored @Injected() var glucoseStogare: GlucoseStorage!

        var alarm: GlucoseAlarm?

        override func subscribe() {
            alarm = glucoseStogare.alarm
        }

        // Add validation helper inside the class
        private func validateSnoozeDuration(_ duration: TimeInterval) -> Bool {
            // Only allow durations matching our defined actions
            NotificationResponseAction.allCases
                .map(\.duration)
                .contains(duration)
        }

        // Add handleSnoozeResponse inside the class
        func handleSnoozeResponse(_ duration: TimeInterval) {
            guard validateSnoozeDuration(duration) else { return }

            Task { @MainActor in
                snoozeUntilDate = Date().addingTimeInterval(duration)
                alarm = glucoseStogare.alarm
            }
        }
    }
}
