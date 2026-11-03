import Foundation
import WatchConnectivity

// MARK: - Send Data to Phone

extension WatchState {
    /// Sends a bolus insulin request to the paired iPhone
    /// - Parameters:
    ///   - amount: The insulin amount to be delivered
    func sendBolusRequest(_ amount: Decimal) {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(.bolus, "Bolus request not sent, phone unreachable")
            return
        }

        WatchLogger.shared.info(.bolus, "Bolus of \(amount) U requested")

        let message: [String: Any] = [
            WatchMessageKeys.bolus: amount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.error(.bolus, "Sending bolus request failed", error: error)
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a carbohydrate entry request to the paired iPhone
    /// - Parameters:
    ///   - amount: The amount of carbs in grams
    ///   - date: The timestamp for the carb entry (defaults to current time)
    func sendCarbsRequest(_ amount: Int, _ date: Date = Date()) {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(.treatments, "Carbs request not sent, phone unreachable")
            return
        }

        WatchLogger.shared.info(.treatments, "Carbs of \(amount) g requested for \(date)")

        let message: [String: Any] = [
            WatchMessageKeys.carbs: amount,
            WatchMessageKeys.date: date.timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.error(.treatments, "Sending carbs request failed", error: error)
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to cancel the current override preset to the paired iPhone
    func sendCancelOverrideRequest() {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(.treatments, "Override cancel not sent, phone unreachable")
            return
        }

        WatchLogger.shared.info(.treatments, "Override cancel requested")

        let message: [String: Any] = [
            WatchMessageKeys.cancelOverride: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.error(.treatments, "Sending override cancel failed", error: error)
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to activate an override preset to the paired iPhone
    /// - Parameter presetName: The name of the override preset to activate
    func sendActivateOverrideRequest(presetName: String) {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(.treatments, "Override request not sent, phone unreachable")
            return
        }

        WatchLogger.shared.info(.treatments, "Override preset \(presetName) requested")

        let message: [String: Any] = [
            WatchMessageKeys.activateOverride: presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.error(.treatments, "Sending override request failed", error: error)
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to cancel the current temporary target to the paired iPhone
    func sendCancelTempTargetRequest() {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(.treatments, "Temp target cancel not sent, phone unreachable")
            return
        }

        WatchLogger.shared.info(.treatments, "Temp target cancel requested")

        let message: [String: Any] = [
            WatchMessageKeys.cancelTempTarget: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.error(.treatments, "Sending temp target cancel failed", error: error)
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to activate a temporary target preset to the paired iPhone
    /// - Parameter presetName: The name of the temporary target preset to activate
    func sendActivateTempTargetRequest(presetName: String) {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(.treatments, "Temp target request not sent, phone unreachable")
            return
        }

        WatchLogger.shared.info(.treatments, "Temp target preset \(presetName) requested")

        let message: [String: Any] = [
            WatchMessageKeys.activateTempTarget: presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.error(.treatments, "Sending temp target request failed", error: error)
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to calculate a bolus recommendation based on the current carbs amount
    func requestBolusRecommendation() {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(.bolus, "Bolus recommendation not requested, phone unreachable")
            return
        }

        WatchLogger.shared.debug(.bolus, "Bolus recommendation requested for \(carbsAmount) g carbs")

        // Show a progress indicator until the phone replies. This keeps the user from
        // tapping the (0 U) "Log Carbs" button before the recommendation has landed.
        DispatchQueue.main.async {
            self.showBolusCalculationProgress = true
        }

        // The phone drops the reply silently if its session is unreachable at reply
        // time, so there is no guaranteed response to clear the flag. Fall back to a
        // timeout that reveals the normal UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.showBolusCalculationProgress {
                self.showBolusCalculationProgress = false
            }
        }

        let message: [String: Any] = [
            WatchMessageKeys.requestBolusRecommendation: true,
            WatchMessageKeys.carbs: carbsAmount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.warning(.bolus, "Requesting bolus recommendation failed", error: error)
            DispatchQueue.main.async {
                self.showBolusCalculationProgress = false
            }
        }
    }

    func requestWatchStateUpdate() {
        guard let session = session else {
            WatchLogger.shared.warning(.connectivity, "No session for a state update")
            return
        }

        guard session.activationState == .activated else {
            WatchLogger.shared.debug(.connectivity, "Session not activated, activating")
            session.activate()
            return
        }

        if session.isReachable {
            WatchLogger.shared.debug(.data, "Requesting a state update from the phone")

            let message = [WatchMessageKeys.requestWatchUpdate: WatchMessageKeys.watchState]

            session.sendMessage(message, replyHandler: nil) { error in
                WatchLogger.shared.warning(.connectivity, "Requesting a state update failed", error: error)
            }
        } else {
            WatchLogger.shared.debug(.connectivity, "Phone unreachable, state update not requested")
        }
    }

    /// Snoozes all alarms on the iPhone for the given duration. A duration of 0 ends the snooze.
    func sendSnoozeRequest(minutes: Int) {
        WatchLogger.shared.debug(.connectivity, "Sending snooze request: \(minutes) min")

        snoozeUntilDate = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : .distantPast
        WatchNotificationHandler.shared.sendSnoozeRequest(minutes: minutes)
    }
}
