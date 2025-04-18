import Foundation
import WatchConnectivity

// MARK: - Send Data to Phone

extension WatchState {
    /// Sends a bolus insulin request to the paired iPhone
    /// - Parameters:
    ///   - amount: The insulin amount to be delivered
    func sendBolusRequest(_ amount: Decimal) {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.log("⌚️ Bolus request aborted: session unreachable")
            return
        }
        
        isBolusCanceled = false // Reset canceled state when starting new bolus
        activeBolusAmount = Double(truncating: amount as NSNumber) // Set active bolus amount

        WatchLogger.shared.log("⌚️ Sending bolus request: \(amount)U")
                WatchLogger.shared.log("⌚️ isBolusCanceled = false, activeBolusAmount = \(activeBolusAmount)")
        
        let message: [String: Any] = [
            WatchMessageKeys.bolus: amount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("Error sending bolus request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
        WatchLogger.shared.log("⌚️ showCommsAnimation = true")
    }

    /// Sends a carbohydrate entry request to the paired iPhone
    /// - Parameters:
    ///   - amount: The amount of carbs in grams
    ///   - date: The timestamp for the carb entry (defaults to current time)
    func sendCarbsRequest(_ amount: Int, _ date: Date = Date()) {
        guard let session = session, session.isReachable else {
                    WatchLogger.shared.log("⌚️ Carbs request aborted: session unreachable")
                    return
                }
        
        WatchLogger.shared.log("⌚️ Sending carbs request: \(amount)g at \(date)")

        let message: [String: Any] = [
            WatchMessageKeys.carbs: amount,
            WatchMessageKeys.date: date.timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("Error sending carbs request: \(error.localizedDescription)")
        }

        // Display pending communication animation
                WatchLogger.shared.log("⌚️ showCommsAnimation = true")
    }

    /// Sends a request to cancel the current override preset to the paired iPhone
    func sendCancelOverrideRequest() {
        guard let session = session, session.isReachable else {
                    WatchLogger.shared.log("⌚️ Cancel override request aborted: session unreachable")
                    return
                }

                WatchLogger.shared.log("⌚️ Sending cancel override request")

        let message: [String: Any] = [
            WatchMessageKeys.cancelOverride: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("⌚️ Error sending cancel override request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
        WatchLogger.shared.log("⌚️ showCommsAnimation = true")
    }

    /// Sends a request to activate an override preset to the paired iPhone
    /// - Parameter presetName: The name of the override preset to activate
    func sendActivateOverrideRequest(presetName: String) {
        guard let session = session, session.isReachable else {
                    WatchLogger.shared.log("⌚️ Activate override request aborted: session unreachable")
                    return
                }

                WatchLogger.shared.log("⌚️ Sending activate override request for preset: \(presetName)")

        let message: [String: Any] = [
            WatchMessageKeys.activateOverride: presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("⌚️ Error sending activate override request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
        WatchLogger.shared.log("⌚️ showCommsAnimation = true")
    }

    /// Sends a request to cancel the current temporary target to the paired iPhone
    func sendCancelTempTargetRequest() {
        guard let session = session, session.isReachable else {
                    WatchLogger.shared.log("⌚️ Cancel temp target request aborted: session unreachable")
                    return
                }

                WatchLogger.shared.log("⌚️ Sending cancel temp target request")

        let message: [String: Any] = [
            WatchMessageKeys.cancelTempTarget: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("⌚️ Error sending cancel temp target request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
        WatchLogger.shared.log("⌚️ showCommsAnimation = true")
    }

    /// Sends a request to activate a temporary target preset to the paired iPhone
    /// - Parameter presetName: The name of the temporary target preset to activate
    func sendActivateTempTargetRequest(presetName: String) {
        guard let session = session, session.isReachable else {
                    WatchLogger.shared.log("⌚️ Activate temp target request aborted: session unreachable")
                    return
                }

                WatchLogger.shared.log("⌚️ Sending activate temp target request for preset: \(presetName)")

        let message: [String: Any] = [
            WatchMessageKeys.activateTempTarget: presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("⌚️ Error sending activate temp target request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
        WatchLogger.shared.log("⌚️ showCommsAnimation = true")
    }

    /// Sends a request to cancel the current bolus delivery to the paired iPhone
    func sendCancelBolusRequest() {
        isBolusCanceled = true

        guard let session = session, session.isReachable else {
                    WatchLogger.shared.log("⌚️ Cancel bolus request aborted: session unreachable")
                    return
                }

                WatchLogger.shared.log("⌚️ Sending cancel bolus request. bolusCanceled = true")
                WatchLogger.shared.log("⌚️ Resetting bolusProgress and activeBolusAmount to 0")

        let message: [String: Any] = [
            WatchMessageKeys.cancelBolus: true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("Error sending cancel bolus request: \(error.localizedDescription)")
        }

        // Reset when cancelled
        bolusProgress = 0
        activeBolusAmount = 0
        WatchLogger.shared.log("⌚️ reset bolusProgress and activeBolusAmount to 0")

        // Display pending communication animation
        showCommsAnimation = true
        WatchLogger.shared.log("⌚️ showCommsAnimation = true")
    }

    /// Sends a request to calculate a bolus recommendation based on the current carbs amount
    func requestBolusRecommendation() {
        guard let session = session, session.isReachable else {
                    WatchLogger.shared.log("⌚️ Bolus recommendation request aborted: session unreachable")
                    return
                }

                WatchLogger.shared.log("⌚️ Requesting bolus recommendation for carbs: \(carbsAmount)")

        let message: [String: Any] = [
            WatchMessageKeys.requestBolusRecommendation: true,
            WatchMessageKeys.carbs: carbsAmount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.log("Error requesting bolus recommendation: \(error.localizedDescription)")
        }

        showBolusCalculationProgress = true
        WatchLogger.shared.log("⌚️ showBolusCalculationProgress = true")
    }

    func requestWatchStateUpdate() {
        guard let session = session else {
                    WatchLogger.shared.log("⌚️ No session available for state update")
                    return
                }

                guard session.activationState == .activated else {
                    WatchLogger.shared.log("⌚️ Session not activated. Activating...")
                    session.activate()
                    return
                }

        if session.isReachable {
                    WatchLogger.shared.log("⌚️ Requesting WatchState update from iPhone")

                    let message = [WatchMessageKeys.requestWatchUpdate: WatchMessageKeys.watchState]

                    session.sendMessage(message, replyHandler: nil) { error in
                        WatchLogger.shared.log("⌚️ Error requesting WatchState update: \(error.localizedDescription)")
                    }
                } else {
                    WatchLogger.shared.log("⌚️ Phone not reachable for WatchState update")
                }
    }
}
