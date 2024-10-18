import SwiftUI

extension Snooze {
    final class StateModel: BaseStateModel<Provider> {
        @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast
        @Injected() var glucoseStogare: GlucoseStorage!

        @Published var alarm: GlucoseAlarm?

        override func subscribe() {
            alarm = glucoseStogare.alarm
        }
    }
}
