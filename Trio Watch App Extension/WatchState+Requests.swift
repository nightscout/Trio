import Foundation
import WatchConnectivity

// MARK: - Send Data to Phone

extension WatchState {
    /// Sends the entry confirmed with the crown: its carbs, if any, then the bolus.
    /// Refuses an entry older than `entryLifetime` and clears it instead.
    func sendConfirmedEntry(bolusAmount amount: Double, at now: Date = Date()) {
        guard refuseIfExpired(at: now) == false else { return }

        let carbs = carbsAmount
        clearEntry()
        if carbs > 0 {
            sendCarbsRequest(carbs, now)
        }
        sendBolusRequest(Decimal(amount))
    }

    /// Sends a carbs-only entry ("Log Carbs"). Refuses an entry older than `entryLifetime` and clears it instead.
    func sendCarbsEntry(_ amount: Int, at now: Date = Date()) {
        guard refuseIfExpired(at: now) == false else { return }

        clearEntry()
        sendCarbsRequest(amount, now)
    }

    private func refuseIfExpired(at now: Date) -> Bool {
        guard !isEntryFresh(at: now) else { return false }
        WatchLogger.shared.warning(.treatments, "Entry older than \(Int(Self.entryLifetime / 60)) min not sent")
        clearEntry()
        handleRequestNotSent(Self.entryExpiredMessage)
        return true
    }

    /// Sends a bolus insulin request to the paired iPhone
    /// - Parameters:
    ///   - amount: The insulin amount to be delivered
    func sendBolusRequest(_ amount: Decimal) {
        guard amount > 0 else {
            WatchLogger.shared.warning(.bolus, "Bolus of \(amount) U not sent, amount must be above 0")
            handleRequestNotSent(Self.invalidBolusAmountMessage)
            return
        }

        guard let session = reachableSession(.bolus, notSentLog: "Bolus request not sent, phone unreachable") else { return }

        WatchLogger.shared.info(.bolus, "Bolus of \(amount) U requested")

        send([WatchMessageKeys.bolus: amount], on: session, .bolus, failureLog: "Sending bolus request failed")
    }

    /// Sends a carbohydrate entry request to the paired iPhone
    /// - Parameters:
    ///   - amount: The amount of carbs in grams
    ///   - date: The timestamp for the carb entry (defaults to current time)
    func sendCarbsRequest(_ amount: Int, _ date: Date = Date()) {
        guard let session = reachableSession(.treatments, notSentLog: "Carbs request not sent, phone unreachable") else { return }

        WatchLogger.shared.info(.treatments, "Carbs of \(amount) g requested for \(date)")

        let message: [String: Any] = [
            WatchMessageKeys.carbs: amount,
            WatchMessageKeys.date: date.timeIntervalSince1970
        ]
        send(message, on: session, .treatments, failureLog: "Sending carbs request failed")
    }

    /// Sends a request to cancel the current override preset to the paired iPhone
    func sendCancelOverrideRequest() {
        guard let session = reachableSession(.treatments, notSentLog: "Override cancel not sent, phone unreachable")
        else { return }

        WatchLogger.shared.info(.treatments, "Override cancel requested")

        send([WatchMessageKeys.cancelOverride: true], on: session, .treatments, failureLog: "Sending override cancel failed")
    }

    /// Sends a request to activate an override preset to the paired iPhone
    /// - Parameter presetName: The name of the override preset to activate
    func sendActivateOverrideRequest(presetName: String) {
        guard let session = reachableSession(.treatments, notSentLog: "Override request not sent, phone unreachable")
        else { return }

        WatchLogger.shared.info(.treatments, "Override preset \(presetName) requested")

        send(
            [WatchMessageKeys.activateOverride: presetName],
            on: session,
            .treatments,
            failureLog: "Sending override request failed"
        )
    }

    /// Sends a request to cancel the current temporary target to the paired iPhone
    func sendCancelTempTargetRequest() {
        guard let session = reachableSession(.treatments, notSentLog: "Temp target cancel not sent, phone unreachable")
        else { return }

        WatchLogger.shared.info(.treatments, "Temp target cancel requested")

        send(
            [WatchMessageKeys.cancelTempTarget: true],
            on: session,
            .treatments,
            failureLog: "Sending temp target cancel failed"
        )
    }

    /// Sends a request to activate a temporary target preset to the paired iPhone
    /// - Parameter presetName: The name of the temporary target preset to activate
    func sendActivateTempTargetRequest(presetName: String) {
        guard let session = reachableSession(.treatments, notSentLog: "Temp target request not sent, phone unreachable")
        else { return }

        WatchLogger.shared.info(.treatments, "Temp target preset \(presetName) requested")

        send(
            [WatchMessageKeys.activateTempTarget: presetName],
            on: session,
            .treatments,
            failureLog: "Sending temp target request failed"
        )
    }

    /// The session when the phone can take a request; otherwise tells the user nothing was sent
    private func reachableSession(_ category: WatchLogEntry.Category, notSentLog: String) -> WCSession? {
        guard let session = session, session.isReachable else {
            WatchLogger.shared.warning(category, notSentLog)
            handleRequestNotSent(Self.phoneUnreachableMessage)
            return nil
        }
        return session
    }

    /// Sends a treatment request and waits for the phone's acknowledgment
    private func send(
        _ message: [String: Any],
        on session: WCSession,
        _ category: WatchLogEntry.Category,
        failureLog: String
    ) {
        beginAwaitingAcknowledgment()

        session.sendMessage(message, replyHandler: nil) { error in
            WatchLogger.shared.error(category, failureLog, error: error)
            DispatchQueue.main.async {
                self.handleMissingAcknowledgment()
            }
        }
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

    /// - Returns: `true` if the request was sent.
    @discardableResult func requestWatchStateUpdate() -> Bool {
        guard let session = session else {
            WatchLogger.shared.warning(.connectivity, "No session for a state update")
            return false
        }

        guard session.activationState == .activated else {
            WatchLogger.shared.debug(.connectivity, "Session not activated, activating")
            session.activate()
            return false
        }

        if session.isReachable {
            WatchLogger.shared.debug(.data, "Requesting a state update from the phone")

            let message = [WatchMessageKeys.requestWatchUpdate: WatchMessageKeys.watchState]

            session.sendMessage(message, replyHandler: { reply in
                DispatchQueue.main.async {
                    // Empty reply: the phone had no state.
                    let accepted = !reply.isEmpty && self.acceptWatchStatePayload(reply)
                    self.endSync(hidingAnimation: !accepted)
                }
            }, errorHandler: { error in
                WatchLogger.shared.warning(.connectivity, "Requesting a state update failed", error: error)
                DispatchQueue.main.async {
                    self.endSync(hidingAnimation: true)
                }
            })
            return true
        } else {
            WatchLogger.shared.debug(.connectivity, "Phone unreachable, state update not requested")
            return false
        }
    }

    /// Snoozes all alarms on the iPhone for the given duration. A duration of 0 ends the snooze.
    func sendSnoozeRequest(minutes: Int) {
        WatchLogger.shared.debug(.connectivity, "Sending snooze request: \(minutes) min")

        snoozeUntilDate = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : .distantPast
        WatchNotificationHandler.shared.sendSnoozeRequest(minutes: minutes)
    }
}
