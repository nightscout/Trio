import Foundation
import WatchConnectivity

// MARK: - Send Data to Phone

extension WatchState {
    /// Sends a bolus insulin request to the paired iPhone
    /// - Parameters:
    ///   - amount: The insulin amount to be delivered
    func sendBolusRequest(_ amount: Decimal) {
        guard let session = session, session.isReachable else { return }
        isBolusCanceled = false // Reset canceled state when starting new bolus
        activeBolusAmount = Double(truncating: amount as NSNumber) // Set active bolus amount

        let message: [String: Any] = [
            WatchMessageKeys.bolus: amount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending bolus request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a carbohydrate entry request to the paired iPhone
    /// - Parameters:
    ///   - amount: The amount of carbs in grams
    ///   - date: The timestamp for the carb entry (defaults to current time)
    func sendCarbsRequest(_ amount: Int, _ date: Date = Date()) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.carbs: amount,
            WatchMessageKeys.date: date.timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending carbs request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to cancel the current override preset to the paired iPhone
    func sendCancelOverrideRequest() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.cancelOverride: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending cancel override request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to activate an override preset to the paired iPhone
    /// - Parameter presetName: The name of the override preset to activate
    func sendActivateOverrideRequest(presetName: String) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.activateOverride: presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending activate override request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to cancel the current temporary target to the paired iPhone
    func sendCancelTempTargetRequest() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.cancelTempTarget: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending cancel temp target request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to activate a temporary target preset to the paired iPhone
    /// - Parameter presetName: The name of the temporary target preset to activate
    func sendActivateTempTargetRequest(presetName: String) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.activateTempTarget: presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending activate temp target request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to cancel the current bolus delivery to the paired iPhone
    func sendCancelBolusRequest() {
        isBolusCanceled = true

        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.cancelBolus: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending cancel bolus request: \(error.localizedDescription)")
        }

        // Reset when cancelled
        bolusProgress = 0
        activeBolusAmount = 0

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a request to calculate a bolus recommendation based on the current carbs amount
    func requestBolusRecommendation() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.requestBolusRecommendation: true,
            WatchMessageKeys.carbs: carbsAmount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error requesting bolus recommendation: \(error.localizedDescription)")
        }

        showBolusCalculationProgress = true
    }

    func requestWatchStateUpdate() {
        guard let session = session, session.activationState == .activated else {
            print("⌚️ Session not activated, activating...")
            session?.activate()
            return
        }

        if session.isReachable {
            print("⌚️ Request an update for watch state from Trio iPhone app...")

            let message = [WatchMessageKeys.requestWatchUpdate: WatchMessageKeys.watchState]

            session.sendMessage(message, replyHandler: nil) { error in
                print("⌚️ Update request for fresh watch state data: \(error.localizedDescription)")
            }
        } else {
            print("⌚️ Phone not reachable for watch state update")
        }
    }
}
