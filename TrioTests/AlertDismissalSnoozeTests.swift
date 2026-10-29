import Foundation
import Testing
import UserNotifications

@testable import Trio

@Suite("Trio Alerts: dismissing an alert snoozes it") struct AlertDismissalSnoozeTests {
    /// The bug this covers: tapping a High notification acknowledged it
    /// outright, and the alarm then stayed silent for the rest of the
    /// excursion. Every way of clearing an alert has to buy a snooze.
    @Test("Tapping a notification snoozes for 15 minutes") func tapSnoozes() {
        #expect(
            BaseTrioAlertManager.snoozeDuration(forActionIdentifier: UNNotificationDefaultActionIdentifier)
                == 15 * 60
        )
    }

    @Test("Swiping a notification away snoozes for 15 minutes") func swipeSnoozes() {
        #expect(
            BaseTrioAlertManager.snoozeDuration(forActionIdentifier: UNNotificationDismissActionIdentifier)
                == 15 * 60
        )
    }

    /// These buttons used to fall through to a plain acknowledgement, so
    /// picking "Snooze 3 hrs" did the same thing as picking OK.
    @Test("A chosen snooze action keeps its own duration") func chosenDurationWins() {
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze15") == 15 * 60)
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze1hr") == 60 * 60)
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze3hr") == 3 * 60 * 60)
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze6hr") == 6 * 60 * 60)
    }

    @Test("Every snooze action maps to its own duration") func everyActionMaps() {
        for action in NotificationResponseAction.allCases {
            #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: action.rawValue) == action.duration)
        }
    }

    /// An action Trio doesn't know still has to leave the alarm able to
    /// return, so it takes the quick snooze rather than silencing anything.
    @Test("An unknown action falls back to the quick snooze") func unknownActionFallsBack() {
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "something.else") == 15 * 60)
    }

    @Test("The quick snooze is the 15-minute action, not a second constant") func oneSourceOfTruth() {
        #expect(BaseTrioAlertManager.quickSnooze == NotificationResponseAction.snooze15.duration)
    }
}
