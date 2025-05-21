//
//  PodCommsSession.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/13/17.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import os.log

public enum PodCommsError: Error {
    case noPodPaired
    case invalidData
    case noResponse
    case emptyResponse
    case podAckedInsteadOfReturningResponse
    case unexpectedPacketType(packetType: PacketType)
    case unexpectedResponse(response: MessageBlockType)
    case unknownResponseType(rawType: UInt8)
    case invalidAddress(address: UInt32, expectedAddress: UInt32)
    case noRileyLinkAvailable
    case unfinalizedBolus
    case unfinalizedTempBasal
    case nonceResyncFailed
    case podSuspended
    case podFault(fault: DetailedStatus)
    case commsError(error: Error)
    case unacknowledgedMessage(sequenceNumber: Int, error: Error)
    case unacknowledgedCommandPending
    case rejectedMessage(errorCode: UInt8)
    case podChange
    case activationTimeExceeded
    case rssiTooLow
    case rssiTooHigh
    case diagnosticMessage(str: String)
    case podIncompatible(str: String)
    case noPodsFound
    case tooManyPodsFound
    case setupNotComplete
}

extension PodCommsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noPodPaired:
            return LocalizedString("No pod paired", comment: "Error message shown when no pod is paired")
        case .invalidData:
            return nil
        case .noResponse:
            return LocalizedString("No response from pod", comment: "Error message shown when no response from pod was received")
        case .emptyResponse:
            return LocalizedString("Empty response from pod", comment: "Error message shown when empty response from pod was received")
        case .podAckedInsteadOfReturningResponse:
            return LocalizedString("Pod sent ack instead of response", comment: "Error message shown when pod sends ack instead of response")
        case .unexpectedPacketType:
            return nil
        case .unexpectedResponse:
            return LocalizedString("Unexpected response from pod", comment: "Error message shown when empty response from pod was received")
        case .unknownResponseType:
            return nil
        case .invalidAddress(address: let address, expectedAddress: let expectedAddress):
            return String(format: LocalizedString("Invalid address 0x%x. Expected 0x%x", comment: "Error message for when unexpected address is received (1: received address) (2: expected address)"), address, expectedAddress)
        case .noRileyLinkAvailable:
            return LocalizedString("No RileyLink available", comment: "Error message shown when no response from pod was received")
        case .unfinalizedBolus:
            return LocalizedString("Bolus in progress", comment: "Error message shown when operation could not be completed due to existing bolus in progress")
        case .unfinalizedTempBasal:
            return LocalizedString("Temp basal in progress", comment: "Error message shown when temp basal could not be set due to existing temp basal in progress")
        case .nonceResyncFailed:
            return nil
        case .podSuspended:
            return LocalizedString("Pod is suspended", comment: "Error message action could not be performed because pod is suspended")
        case .podFault(let fault):
            let faultDescription = String(describing: fault.faultEventCode)
            return String(format: LocalizedString("Pod Fault: %1$@", comment: "Format string for pod fault code"), faultDescription)
        case .commsError(let error):
            return error.localizedDescription
        case .unacknowledgedMessage(_, let error):
            return error.localizedDescription
        case .unacknowledgedCommandPending:
            return LocalizedString("Communication issue: Unacknowledged command pending.", comment: "Error message when command is rejected because an unacknowledged command is pending.")
        case .rejectedMessage(let errorCode):
            return String(format: LocalizedString("Command error %1$u", comment: "Format string for invalid message error code (1: error code number)"), errorCode)
        case .podChange:
            return LocalizedString("Unexpected pod change", comment: "Format string for unexpected pod change")
        case .activationTimeExceeded:
            return LocalizedString("Activation time exceeded", comment: "Format string for activation time exceeded")
        case .rssiTooLow: // occurs when pod is too far for reliable pairing, but can sometimes occur at other distances & positions
            return LocalizedString("Poor signal strength", comment: "Format string for poor pod signal strength")
        case .rssiTooHigh: // only occurs when pod is too close for reliable pairing
            return LocalizedString("Signal strength too high", comment: "Format string for pod signal strength too high")
        case .diagnosticMessage(let str):
            return str
        case .podIncompatible(let str):
            return str
        case .noPodsFound:
            return LocalizedString("No pods found", comment: "Error message for PodCommsError.noPodsFound")
        case .tooManyPodsFound:
            return LocalizedString("Too many pods found", comment: "Error message for PodCommsError.tooManyPodsFound")
        case .setupNotComplete:
            return LocalizedString("Pod setup is not complete", comment: "Error description when pod setup is not complete")
        }
    }

//    public var failureReason: String? {
//        return nil
//    }

    public var recoverySuggestion: String? {
        switch self {
        case .noPodPaired:
            return nil
        case .invalidData:
            return nil
        case .noResponse:
            return LocalizedString("Please try repositioning the pod or the RileyLink and try again", comment: "Recovery suggestion when no response is received from pod")
        case .emptyResponse:
            return nil
        case .podAckedInsteadOfReturningResponse:
            return LocalizedString("Try again", comment: "Recovery suggestion when ack received instead of response")
        case .unexpectedPacketType:
            return nil
        case .unexpectedResponse:
            return nil
        case .unknownResponseType:
            return nil
        case .invalidAddress:
            return LocalizedString("Crosstalk possible. Please move to a new location", comment: "Recovery suggestion when unexpected address received")
        case .noRileyLinkAvailable:
            return LocalizedString("Make sure your RileyLink is nearby and powered on", comment: "Recovery suggestion when no RileyLink is available")
        case .unfinalizedBolus:
            return LocalizedString("Wait for existing bolus to finish, or cancel bolus", comment: "Recovery suggestion when operation could not be completed due to existing bolus in progress")
        case .unfinalizedTempBasal:
            return LocalizedString("Wait for existing temp basal to finish, or suspend to cancel", comment: "Recovery suggestion when operation could not be completed due to existing temp basal in progress")
        case .nonceResyncFailed:
            return nil
        case .podSuspended:
            return LocalizedString("Resume delivery", comment: "Recovery suggestion when pod is suspended")
        case .podFault:
            return nil
        case .commsError:
            return nil
        case .unacknowledgedMessage:
            return nil
        case .unacknowledgedCommandPending:
            return nil
        case .rejectedMessage:
            return nil
        case .podChange:
            return LocalizedString("Please bring only original pod in range or deactivate original pod", comment: "Recovery suggestion on unexpected pod change")
        case .activationTimeExceeded:
            return nil
        case .rssiTooLow:
            return LocalizedString("Please reposition the RileyLink relative to the pod", comment: "Recovery suggestion when pairing signal strength is too low")
        case .rssiTooHigh:
            return LocalizedString("Please reposition the RileyLink further from the pod", comment: "Recovery suggestion when pairing signal strength is too high")
        case .diagnosticMessage:
            return nil
        case .podIncompatible:
            return nil
        case .noPodsFound:
            return LocalizedString("Make sure your pod is filled and nearby.", comment: "Recovery suggestion for PodCommsError.noPodsFound")
        case .tooManyPodsFound:
            return LocalizedString("Move to a new area away from any other pods and try again.", comment: "Recovery suggestion for PodCommsError.tooManyPodsFound")
        case .setupNotComplete:
            return nil
        }
    }

    public var isFaulted: Bool {
        switch self {
        case .podFault, .activationTimeExceeded, .podIncompatible:
            return true
        default:
            return false
        }
    }
}

public protocol PodCommsSessionDelegate: AnyObject {
    func podCommsSession(_ podCommsSession: PodCommsSession, didChange state: PodState)
}

public class PodCommsSession {
    public let log = OSLog(category: "PodCommsSession")

    private var podState: PodState {
        didSet {
            assertOnSessionQueue()
            delegate.podCommsSession(self, didChange: podState)
        }
    }

    private unowned let delegate: PodCommsSessionDelegate
    private var transport: MessageTransport

    // used for testing
    var mockCurrentDate: Date?
    var currentDate: Date {
        return mockCurrentDate ?? Date()
    }

    init(podState: PodState, transport: MessageTransport, delegate: PodCommsSessionDelegate) {
        self.podState = podState
        self.transport = transport
        self.delegate = delegate
        self.transport.delegate = self
    }

    // Handles updating PodState on first pod fault seen
    private func handlePodFault(fault: DetailedStatus) {
        if podState.fault == nil {
            podState.fault = fault // save the first fault returned
            if let activatedAt = podState.activatedAt {
                podState.activeTime = currentDate.timeIntervalSince(activatedAt)
            } else {
                podState.activeTime = fault.faultEventTimeSinceActivation
            }
            handleCancelDosing(deliveryType: .all, bolusNotDelivered: fault.bolusNotDelivered)
            let derivedStatusResponse = StatusResponse(detailedStatus: fault)
            if podState.unacknowledgedCommand != nil {
                recoverUnacknowledgedCommand(using: derivedStatusResponse)
            }
            podState.updateFromStatusResponse(derivedStatusResponse, at: currentDate)
        }
        log.error("Pod Fault: %@", String(describing: fault))
    }

    // Will throw either PodCommsError.podFault or PodCommsError.activationTimeExceeded
    private func throwPodFault(fault: DetailedStatus) throws {
        handlePodFault(fault: fault)
        if fault.podProgressStatus == .activationTimeExceeded {
            // avoids a confusing "No fault" error when activation time is exceeded
            throw PodCommsError.activationTimeExceeded
        }
        throw PodCommsError.podFault(fault: fault)
    }

    /// Performs a message exchange, handling nonce resync, pod faults
    ///
    /// - Parameters:
    ///   - messageBlocks: The message blocks to send
    ///   - beepBlock: Optional confirmation beep block message to append to the message blocks to send
    ///   - expectFollowOnMessage: If true, the pod will expect another message within 4 minutes, or will alarm with an 0x33 (51) fault.
    /// - Returns: The received message response
    /// - Throws:
    ///     - PodCommsError.noResponse
    ///     - PodCommsError.podFault
    ///     - PodCommsError.unexpectedResponse
    ///     - PodCommsError.rejectedMessage
    ///     - PodCommsError.nonceResyncFailed
    ///     - MessageError
    ///     - RileyLinkDeviceError
    func send<T: MessageBlock>(_ messageBlocks: [MessageBlock], beepBlock: MessageBlock? = nil, expectFollowOnMessage: Bool = false) throws -> T {

        var triesRemaining = 2  // Retries only happen for nonce resync
        var blocksToSend = messageBlocks

        // If a beep block was specified & pod isn't faulted, append the beep block to emit the confirmation beep
        if let beepBlock = beepBlock, podState.isFaulted == false {
            blocksToSend += [beepBlock]
        }

        if blocksToSend.contains(where: { $0 as? NonceResyncableMessageBlock != nil }) {
            podState.advanceToNextNonce()
        }

        let messageNumber = transport.messageNumber

        var sentNonce: UInt32?

        while (triesRemaining > 0) {
            triesRemaining -= 1

            for command in blocksToSend {
                if let nonceBlock = command as? NonceResyncableMessageBlock {
                    sentNonce = nonceBlock.nonce
                    break // N.B. all nonce commands in single message should have the same value
                }
            }

            let message = Message(address: podState.address, messageBlocks: blocksToSend, sequenceNum: messageNumber, expectFollowOnMessage: expectFollowOnMessage)

            // Clear the lastDeliveryStatusReceived variable which is used to guard against possible 0x31 pod faults
            podState.lastDeliveryStatusReceived = nil

            let response = try transport.sendMessage(message)

            // Simulate fault
            //let podInfoResponse = try PodInfoResponse(encodedData: Data(hexadecimalString: "0216020d0000000000ab6a038403ff03860000285708030d0000")!)
            //let response = Message(address: podState.address, messageBlocks: [podInfoResponse], sequenceNum: message.sequenceNum)

            if let responseMessageBlock = response.messageBlocks[0] as? T {
                log.info("POD Response: %{public}@", String(describing: responseMessageBlock))
                return responseMessageBlock
            }


            if let fault = response.fault {
                try throwPodFault(fault: fault) // always throws
            }

            let responseType = response.messageBlocks[0].blockType
            guard let errorResponse = response.messageBlocks[0] as? ErrorResponse else {
                log.error("Unexpected response: %{public}@", String(describing: response.messageBlocks[0]))
                throw PodCommsError.unexpectedResponse(response: responseType)
            }

            switch errorResponse.errorResponseType {
            case .badNonce(let nonceResyncKey):
                guard let sentNonce = sentNonce else {
                    log.error("Unexpected bad nonce response: %{public}@", String(describing: response.messageBlocks[0]))
                    throw PodCommsError.unexpectedResponse(response: responseType)
                }
                podState.resyncNonce(syncWord: nonceResyncKey, sentNonce: sentNonce, messageSequenceNum: Int(message.sequenceNum))
                log.info("resyncNonce(syncWord: 0x%02x, sentNonce: 0x%04x, messageSequenceNum: %d) -> 0x%04x", nonceResyncKey, sentNonce, message.sequenceNum, podState.currentNonce)
                blocksToSend = blocksToSend.map({ (block) -> MessageBlock in
                    if var resyncableBlock = block as? NonceResyncableMessageBlock {
                        log.info("Replaced old nonce 0x%04x with resync nonce 0x%04x", resyncableBlock.nonce, podState.currentNonce)
                        resyncableBlock.nonce = podState.currentNonce
                        return resyncableBlock
                    }
                    return block
                })
                podState.advanceToNextNonce()
                break
            case .nonretryableError(let errorCode, let faultEventCode, let podProgress):
                log.error("Command error: code %u, %{public}@, pod progress %{public}@", errorCode, String(describing: faultEventCode), String(describing: podProgress))
                throw PodCommsError.rejectedMessage(errorCode: errorCode)
            }
        }
        throw PodCommsError.nonceResyncFailed
    }

    // Returns time at which prime is expected to finish.
    public func prime() throws -> TimeInterval {
        let primeDuration: TimeInterval = .seconds(Pod.primeUnits / Pod.primeDeliveryRate) + 3 // as per PDM

        // If priming has never been attempted on this pod, handle the pre-prime setup tasks.
        // A FaultConfig can only be done before the prime bolus or the pod will generate an 049 fault.
        if podState.setupProgress.primingNeverAttempted {
            // This FaultConfig command will set Tab5[$16] to 0 during pairing, which disables $6x faults
            let _: StatusResponse = try send([FaultConfigCommand(nonce: podState.currentNonce, tab5Sub16: 0, tab5Sub17: 0)])

            // Set up the finish pod setup reminder alert which beeps every 5 minutes for 1 hour
            let finishSetupReminder = PodAlert.finishSetupReminder
            try configureAlerts([finishSetupReminder])
        } else {
            // Not the first time through, check to see if prime bolus was successfully started
            let status: StatusResponse = try send([GetStatusCommand()])
            podState.updateFromStatusResponse(status, at: currentDate)
            if status.podProgressStatus == .priming || status.podProgressStatus == .primingCompleted {
                podState.setupProgress = .priming
                return podState.primeFinishTime?.timeIntervalSinceNow ?? primeDuration
            }
        }

        // Mark Pod.primeUnits (2.6U) bolus delivery with Pod.primeDeliveryRate (1) between pulses for prime

        let primeFinishTime = currentDate + primeDuration
        podState.primeFinishTime = primeFinishTime
        podState.setupProgress = .startingPrime

        let timeBetweenPulses = TimeInterval(seconds: Pod.secondsPerPrimePulse)
        let scheduleCommand = SetInsulinScheduleCommand(nonce: podState.currentNonce, units: Pod.primeUnits, timeBetweenPulses: timeBetweenPulses)
        let bolusExtraCommand = BolusExtraCommand(units: Pod.primeUnits, timeBetweenPulses: timeBetweenPulses)
        let status: StatusResponse = try send([scheduleCommand, bolusExtraCommand])
        podState.updateFromStatusResponse(status, at: currentDate)
        podState.setupProgress = .priming
        return primeFinishTime.timeIntervalSinceNow
    }

    public func programInitialBasalSchedule(_ basalSchedule: BasalSchedule, scheduleOffset: TimeInterval) throws {
        if podState.setupProgress == .settingInitialBasalSchedule {
            // We started basal schedule programming, but didn't get confirmation somehow, so check status
            let status: StatusResponse = try send([GetStatusCommand()])
            podState.updateFromStatusResponse(status, at: currentDate)
            if status.podProgressStatus == .basalInitialized {
                podState.setupProgress = .initialBasalScheduleSet
                podState.finalizedDoses.append(UnfinalizedDose(resumeStartTime: currentDate, scheduledCertainty: .certain, insulinType: podState.insulinType))
                return
            }
        }

        podState.setupProgress = .settingInitialBasalSchedule
        // Set basal schedule
        let _ = try setBasalSchedule(schedule: basalSchedule, scheduleOffset: scheduleOffset)
        podState.setupProgress = .initialBasalScheduleSet
        podState.finalizedDoses.append(UnfinalizedDose(resumeStartTime: currentDate, scheduledCertainty: .certain, insulinType: podState.insulinType))
    }

    // Configures the given pod alert(s) and registers the newly configured alert slot(s).
    // When re-configuring all the pod alerts for a silence pod toggle, the optional acknowledgeAll can be
    // specified to first acknowledge and clear all possible pending pod alerts and pod alert configurations.
    @discardableResult
    func configureAlerts(_ alerts: [PodAlert], acknowledgeAll: Bool = false, beepBlock: MessageBlock? = nil) throws -> StatusResponse {
        let configurations = alerts.map { $0.configuration }
        let configureAlerts = ConfigureAlertsCommand(nonce: podState.currentNonce, configurations: configurations)
        let blocksToSend: [MessageBlock]
        if acknowledgeAll {
            // Do the acknowledgeAllAlerts command first to clear all previous pod alert configurations.
            let acknowledgeAllAlerts = AcknowledgeAlertCommand(nonce: podState.currentNonce, alerts: AlertSet(rawValue: ~0))
            blocksToSend = [acknowledgeAllAlerts, configureAlerts]
        } else {
            blocksToSend = [configureAlerts]
        }
        let status: StatusResponse = try send(blocksToSend, beepBlock: beepBlock)
        for alert in alerts {
            podState.registerConfiguredAlert(slot: alert.configuration.slot, alert: alert)
        }
        podState.updateFromStatusResponse(status, at: currentDate)
        return status
    }

    // emits the specified beep type and sets the completion beep flags, doesn't throw
    public func beepConfig(beepType: BeepType, tempBasalCompletionBeep: Bool, bolusCompletionBeep: Bool) -> Result<StatusResponse, Error> {
        if let fault = self.podState.fault {
            log.info("Skip beep config with faulted pod")
            return .failure(PodCommsError.podFault(fault: fault))
        }

        let beepConfigCommand = BeepConfigCommand(beepType: beepType, tempBasalCompletionBeep: tempBasalCompletionBeep, bolusCompletionBeep: bolusCompletionBeep)
        do {
            let statusResponse: StatusResponse = try send([beepConfigCommand])
            podState.updateFromStatusResponse(statusResponse, at: currentDate)
            return .success(statusResponse)
        } catch let error {
            return .failure(error)
        }
    }

    private func markSetupProgressCompleted(statusResponse: StatusResponse) {
        if (podState.setupProgress != .completed) {
            podState.setupProgress = .completed
            podState.setupUnitsDelivered = statusResponse.insulinDelivered // stash the current insulin delivered value as the baseline
            log.info("Total setup units delivered: %@", String(describing: statusResponse.insulinDelivered))
        }
    }

    public func insertCannula(optionalAlerts: [PodAlert] = [], silent: Bool) throws -> TimeInterval {
        let cannulaInsertionUnits = Pod.cannulaInsertionUnits + Pod.cannulaInsertionUnitsExtra

        guard podState.activatedAt != nil else {
            throw PodCommsError.noPodPaired
        }

        if podState.setupProgress == .startingInsertCannula || podState.setupProgress == .cannulaInserting {
            // We started cannula insertion, but didn't get confirmation somehow, so check status
            let status: StatusResponse = try send([GetStatusCommand()])
            if status.podProgressStatus == .insertingCannula {
                podState.setupProgress = .cannulaInserting
                podState.updateFromStatusResponse(status, at: currentDate)
                // return a non-zero wait time based on the bolus not yet delivered
                return (status.bolusNotDelivered / Pod.primeDeliveryRate) + 1
            }
            if status.podProgressStatus.readyForDelivery {
                markSetupProgressCompleted(statusResponse: status)
                podState.updateFromStatusResponse(status, at: currentDate)
                return TimeInterval(0) // Already done; no need to wait
            }
            podState.updateFromStatusResponse(status, at: currentDate)
        } else {
            let elapsed: TimeInterval = -(podState.podTimeUpdated?.timeIntervalSinceNow ?? 0)
            let podTime = podState.podTime + elapsed

            // Configure the mandatory Pod Alerts for shutdown imminent alert (79 hours) and pod expiration alert (72 hours) along with any optional alerts
            let shutdownImminentAlarm = PodAlert.shutdownImminent(offset: podTime, absAlertTime: Pod.serviceDuration - Pod.endOfServiceImminentWindow, silent: silent)
            let expirationAdvisoryAlarm = PodAlert.expired(offset: podTime, absAlertTime: Pod.nominalPodLife, duration: Pod.expirationAdvisoryWindow, silent: silent)
            try configureAlerts([expirationAdvisoryAlarm, shutdownImminentAlarm] + optionalAlerts)
        }

        // Mark cannulaInsertionUnits (0.5U) bolus delivery with Pod.secondsPerPrimePulse (1) between pulses for cannula insertion

        let timeBetweenPulses = TimeInterval(seconds: Pod.secondsPerPrimePulse)
        let bolusScheduleCommand = SetInsulinScheduleCommand(nonce: podState.currentNonce, units: cannulaInsertionUnits, timeBetweenPulses: timeBetweenPulses)

        podState.setupProgress = .startingInsertCannula
        let bolusExtraCommand = BolusExtraCommand(units: cannulaInsertionUnits, timeBetweenPulses: timeBetweenPulses)
        let status2: StatusResponse = try send([bolusScheduleCommand, bolusExtraCommand])
        podState.updateFromStatusResponse(status2, at: currentDate)

        podState.setupProgress = .cannulaInserting
        return status2.bolusNotDelivered / Pod.primeDeliveryRate // seconds for the cannula insert bolus to finish
    }

    public func checkInsertionCompleted() throws {
        if podState.setupProgress == .cannulaInserting {
            let response: StatusResponse = try send([GetStatusCommand()])
            if response.podProgressStatus.readyForDelivery {
                markSetupProgressCompleted(statusResponse: response)
            }
            podState.updateFromStatusResponse(response, at: currentDate)
        }
    }

    // Throws SetBolusError
    public enum DeliveryCommandResult {
        case success(statusResponse: StatusResponse)
        case certainFailure(error: PodCommsError)
        case unacknowledged(error: PodCommsError)
    }

    public enum CancelDeliveryResult {
        case success(statusResponse: StatusResponse, canceledDose: UnfinalizedDose?)
        case certainFailure(error: PodCommsError)
        case unacknowledged(error: PodCommsError)
    }


    public func bolus(units: Double, automatic: Bool = false, acknowledgementBeep: Bool = false, completionBeep: Bool = false, programReminderInterval: TimeInterval = 0, extendedUnits: Double = 0.0, extendedDuration: TimeInterval = 0) -> DeliveryCommandResult {

        guard podState.unacknowledgedCommand == nil else {
            return DeliveryCommandResult.certainFailure(error: .unacknowledgedCommandPending)
        }

        let timeBetweenPulses = TimeInterval(seconds: Pod.secondsPerBolusPulse)
        let bolusScheduleCommand = SetInsulinScheduleCommand(nonce: podState.currentNonce, units: units, timeBetweenPulses: timeBetweenPulses, extendedUnits: extendedUnits, extendedDuration: extendedDuration)

        // Do a get status here to verify that there isn't an on-going bolus in progress if the last bolus command
        // is still not finalized OR we don't have the last pod delivery status confirming that no bolus is active.
        if podState.unfinalizedBolus != nil || podState.lastDeliveryStatusReceived == nil || podState.lastDeliveryStatusReceived!.bolusing {
            if let statusResponse: StatusResponse = try? send([GetStatusCommand()]) {
                podState.updateFromStatusResponse(statusResponse, at: currentDate)
                guard podState.unfinalizedBolus == nil else {
                    log.default("bolus: pod is still bolusing")
                    return DeliveryCommandResult.certainFailure(error: .unfinalizedBolus)
                }
            } else {
                log.default("bolus: failed to read pod status to verify there is no bolus running")
                return DeliveryCommandResult.certainFailure(error: .noResponse)
            }
        }

        let bolusExtraCommand = BolusExtraCommand(units: units, timeBetweenPulses: timeBetweenPulses, extendedUnits: extendedUnits, extendedDuration: extendedDuration, acknowledgementBeep: acknowledgementBeep, completionBeep: completionBeep, programReminderInterval: programReminderInterval)
        do {
            podState.unacknowledgedCommand = PendingCommand.program(.bolus(volume: units, automatic: automatic), transport.messageNumber, currentDate)
            let statusResponse: StatusResponse = try send([bolusScheduleCommand, bolusExtraCommand])
            podState.unacknowledgedCommand = nil
            podState.unfinalizedBolus = UnfinalizedDose(bolusAmount: units, startTime: currentDate, scheduledCertainty: .certain, insulinType: podState.insulinType, automatic: automatic)
            podState.updateFromStatusResponse(statusResponse, at: currentDate)
            return DeliveryCommandResult.success(statusResponse: statusResponse)
        } catch PodCommsError.unacknowledgedMessage(let seq, let error) {
            podState.unacknowledgedCommand = podState.unacknowledgedCommand?.commsFinished
            log.error("Unacknowledged bolus: command seq = %d, error = %{public}@", seq, String(describing: error))
            return DeliveryCommandResult.unacknowledged(error: .commsError(error: error))
        } catch let error {
            podState.unacknowledgedCommand = nil
            return DeliveryCommandResult.certainFailure(error: .commsError(error: error))
        }
    }

    public func setTempBasal(rate: Double, duration: TimeInterval, isHighTemp: Bool, automatic: Bool, acknowledgementBeep: Bool = false, completionBeep: Bool = false, programReminderInterval: TimeInterval = 0) -> DeliveryCommandResult {

        guard podState.unacknowledgedCommand == nil else {
            return DeliveryCommandResult.certainFailure(error: .unacknowledgedCommandPending)
        }

        let tempBasalCommand = SetInsulinScheduleCommand(nonce: podState.currentNonce, tempBasalRate: rate, duration: duration)
        let tempBasalExtraCommand = TempBasalExtraCommand(rate: rate, duration: duration, acknowledgementBeep: acknowledgementBeep, completionBeep: completionBeep, programReminderInterval: programReminderInterval)

        guard podState.unfinalizedBolus?.isFinished() != false else {
            return DeliveryCommandResult.certainFailure(error: .unfinalizedBolus)
        }

        let startTime = currentDate

        do {
            podState.unacknowledgedCommand = PendingCommand.program(.tempBasal(unitsPerHour: rate, duration: duration, isHighTemp: isHighTemp, automatic: automatic), transport.messageNumber, startTime)
            let status: StatusResponse = try send([tempBasalCommand, tempBasalExtraCommand])
            podState.unacknowledgedCommand = nil
            podState.unfinalizedTempBasal = UnfinalizedDose(tempBasalRate: rate, startTime: startTime, duration: duration, isHighTemp: isHighTemp, automatic: automatic, scheduledCertainty: .certain, insulinType: podState.insulinType)
            podState.updateFromStatusResponse(status, at: currentDate)
            return DeliveryCommandResult.success(statusResponse: status)
        } catch PodCommsError.unacknowledgedMessage(let seq, let error) {
            podState.unacknowledgedCommand = podState.unacknowledgedCommand?.commsFinished
            log.error("Unacknowledged temp basal: command seq = %d, error = %{public}@", seq, String(describing: error))
            return DeliveryCommandResult.unacknowledged(error: .commsError(error: error))
        } catch let error {
            podState.unacknowledgedCommand = nil
            return DeliveryCommandResult.certainFailure(error: .commsError(error: error))
        }
    }

    @discardableResult
    private func handleCancelDosing(deliveryType: CancelDeliveryCommand.DeliveryType, bolusNotDelivered: Double) -> UnfinalizedDose? {
        var canceledDose: UnfinalizedDose? = nil
        let now = currentDate

        if deliveryType.contains(.basal) {
            podState.unfinalizedSuspend = UnfinalizedDose(suspendStartTime: now, scheduledCertainty: .certain)
            podState.suspendState = .suspended(now)
        }

        if let unfinalizedTempBasal = podState.unfinalizedTempBasal,
            let finishTime = unfinalizedTempBasal.finishTime,
            deliveryType.contains(.tempBasal),
            finishTime > now
        {
            podState.unfinalizedTempBasal?.cancel(at: now)
            if !deliveryType.contains(.basal) {
                podState.suspendState = .resumed(now)
            }
            canceledDose = podState.unfinalizedTempBasal
            log.info("Interrupted temp basal: %@", String(describing: canceledDose))
        }

        if let unfinalizedBolus = podState.unfinalizedBolus,
            let finishTime = unfinalizedBolus.finishTime,
            deliveryType.contains(.bolus),
            finishTime > now
        {
            podState.unfinalizedBolus?.cancel(at: now, withRemaining: bolusNotDelivered)
            canceledDose = podState.unfinalizedBolus
            log.info("Interrupted bolus: %@", String(describing: canceledDose))
        }

        return canceledDose
    }

    // Suspends insulin delivery and sets appropriate podSuspendedReminder & suspendTimeExpired alerts.
    // A nil suspendReminder is an untimed suspend with no suspend reminders.
    // A suspendReminder of 0 is an untimed suspend which only uses podSuspendedReminder alert beeps.
    // A suspendReminder of 1-5 minutes will only use suspendTimeExpired alert beeps.
    // A suspendReminder of > 5 min will have periodic podSuspendedReminder beeps followed by suspendTimeExpired alerts.
    // The configured alerts will set up as silent pod alerts if silent is true.
    public func suspendDelivery(suspendReminder: TimeInterval? = nil, silent: Bool, beepBlock: MessageBlock? = nil) -> CancelDeliveryResult {

        guard podState.unacknowledgedCommand == nil else {
            return .certainFailure(error: .unacknowledgedCommandPending)
        }

        guard podState.setupProgress == .completed else {
            // A cancel delivery command before pod setup is complete will fault the pod
            return .certainFailure(error: PodCommsError.setupNotComplete)
        }

        do {
            var alertConfigurations: [AlertConfiguration] = []
            var podSuspendedReminderAlert: PodAlert? = nil
            var suspendTimeExpiredAlert: PodAlert? = nil
            let suspendTime: TimeInterval = suspendReminder != nil ? suspendReminder! : 0
            let elapsed: TimeInterval = -(podState.podTimeUpdated?.timeIntervalSinceNow ?? 0)
            let podTime = podState.podTime + elapsed
            log.debug("suspendDelivery: podState.podTime=%@, elapsed=%.2fs, computed timeActive %@", podState.podTime.timeIntervalStr, elapsed, podTime.timeIntervalStr)

            let cancelDeliveryCommand = CancelDeliveryCommand(nonce: podState.currentNonce, deliveryType: .all, beepType: .noBeepCancel)
            var commandsToSend: [MessageBlock] = [cancelDeliveryCommand]

            // podSuspendedReminder provides a periodic pod suspended reminder beep until the specified suspend time.
            if suspendReminder != nil && (suspendTime == 0 || suspendTime > .minutes(5)) {
                // using reminder beeps for an untimed or long enough suspend time requiring pod suspended reminders
                podSuspendedReminderAlert = PodAlert.podSuspendedReminder(active: true, offset: podTime, suspendTime: suspendTime, silent: silent)
                alertConfigurations += [podSuspendedReminderAlert!.configuration]
            }

            // suspendTimeExpired provides suspend time expired alert beeping after the expected suspend time has passed.
            if suspendTime > 0 {
                // a timed suspend using a suspend time expired alert
                suspendTimeExpiredAlert = PodAlert.suspendTimeExpired(offset: podTime, suspendTime: suspendTime, silent: silent)
                alertConfigurations += [suspendTimeExpiredAlert!.configuration]
            }

            // append a ConfigureAlert command if we have any reminder alerts for this suspend
            if alertConfigurations.count != 0 {
                let configureAlerts = ConfigureAlertsCommand(nonce: podState.currentNonce, configurations: alertConfigurations)
                commandsToSend += [configureAlerts]
            }

            podState.unacknowledgedCommand = PendingCommand.stopProgram(.all, transport.messageNumber, currentDate)
            let status: StatusResponse = try send(commandsToSend, beepBlock: beepBlock)
            podState.unacknowledgedCommand = nil
            let canceledDose = handleCancelDosing(deliveryType: .all, bolusNotDelivered: status.bolusNotDelivered)
            podState.updateFromStatusResponse(status, at: currentDate)

            if let alert = podSuspendedReminderAlert {
                podState.registerConfiguredAlert(slot: alert.configuration.slot, alert: alert)
            }
            if let alert = suspendTimeExpiredAlert {
                podState.registerConfiguredAlert(slot: alert.configuration.slot, alert: alert)
            }

            return CancelDeliveryResult.success(statusResponse: status, canceledDose: canceledDose)

        } catch PodCommsError.unacknowledgedMessage(let seq, let error) {
            podState.unacknowledgedCommand = podState.unacknowledgedCommand?.commsFinished
            log.error("Unacknowledged suspend: command seq = %d, error = %{public}@", seq, String(describing: error))
            return .unacknowledged(error: .commsError(error: error))
        } catch let error {
            podState.unacknowledgedCommand = nil
            return .certainFailure(error: .commsError(error: error))
        }
    }

    // Cancels any suspend related alerts, called when setting a basal schedule with active suspend alerts
    @discardableResult
    private func cancelSuspendAlerts() throws -> StatusResponse {

        do {
            let podSuspendedReminder = PodAlert.podSuspendedReminder(active: false, offset: 0, suspendTime: 0)
            let suspendTimeExpired = PodAlert.suspendTimeExpired(offset: 0, suspendTime: 0) // A suspendTime of 0 deactivates this alert

            let status = try configureAlerts([podSuspendedReminder, suspendTimeExpired])
            return status
        } catch let error {
            throw error
        }
    }

    // Cancel beeping can be done implemented using beepType (for a single delivery type) or a separate confirmation beep message block (for cancel all).
    // N.B., Using the built-in cancel delivery command beepType method when cancelling all insulin delivery will emit 3 different sets of cancel beeps!!!
    public func cancelDelivery(deliveryType: CancelDeliveryCommand.DeliveryType, beepType: BeepType = .noBeepCancel, beepBlock: MessageBlock? = nil) -> CancelDeliveryResult {

        guard podState.unacknowledgedCommand == nil else {
            return .certainFailure(error: .unacknowledgedCommandPending)
        }

        guard podState.setupProgress == .completed else {
            // A cancel delivery command before pod setup is complete will fault the pod
            return .certainFailure(error: PodCommsError.setupNotComplete)
        }

        do {
            podState.unacknowledgedCommand = PendingCommand.stopProgram(deliveryType, transport.messageNumber, currentDate)
            let cancelDeliveryCommand = CancelDeliveryCommand(nonce: podState.currentNonce, deliveryType: deliveryType, beepType: beepType)
            let status: StatusResponse = try send([cancelDeliveryCommand], beepBlock: beepBlock)
            podState.unacknowledgedCommand = nil

            let canceledDose = handleCancelDosing(deliveryType: deliveryType, bolusNotDelivered: status.bolusNotDelivered)
            podState.updateFromStatusResponse(status, at: currentDate)

            return CancelDeliveryResult.success(statusResponse: status, canceledDose: canceledDose)
        } catch PodCommsError.unacknowledgedMessage(let seq, let error) {
            podState.unacknowledgedCommand = podState.unacknowledgedCommand?.commsFinished
            log.debug("Unacknowledged stop program: command seq = %d", seq)
            return .unacknowledged(error: .commsError(error: error))
        } catch let error {
            podState.unacknowledgedCommand = nil
            return .certainFailure(error: .commsError(error: error))
        }
    }

    public func setTime(timeZone: TimeZone, basalSchedule: BasalSchedule, date: Date, acknowledgementBeep: Bool = false) throws -> StatusResponse {
        guard podState.unacknowledgedCommand == nil else {
            throw PodCommsError.unacknowledgedCommandPending
        }

        let result = cancelDelivery(deliveryType: .all)
        switch result {
        case .certainFailure(let error):
            throw error
        case .unacknowledged(let error):
            throw error
        case .success:
            let scheduleOffset = timeZone.scheduleOffset(forDate: date)
            let status = try setBasalSchedule(schedule: basalSchedule, scheduleOffset: scheduleOffset, acknowledgementBeep: acknowledgementBeep)
            return status
        }
    }

    public func setBasalSchedule(schedule: BasalSchedule, scheduleOffset: TimeInterval, acknowledgementBeep: Bool = false, programReminderInterval: TimeInterval = 0) throws -> StatusResponse {

        guard podState.unacknowledgedCommand == nil else {
            throw PodCommsError.unacknowledgedCommandPending
        }

        let basalScheduleCommand = SetInsulinScheduleCommand(nonce: podState.currentNonce, basalSchedule: schedule, scheduleOffset: scheduleOffset)
        let basalExtraCommand = BasalScheduleExtraCommand.init(schedule: schedule, scheduleOffset: scheduleOffset, acknowledgementBeep: acknowledgementBeep, programReminderInterval: programReminderInterval)

        do {
            if !podState.isSuspended || podState.lastDeliveryStatusReceived == nil || !podState.lastDeliveryStatusReceived!.suspended {
                // The podState or the last pod delivery status return indicates that the pod is not currently suspended.
                // So execute a cancel all command here before setting the basal to prevent a possible 0x31 pod fault,
                // but only when the pod startup is complete as a cancel command during pod setup also fault the pod!
                if podState.setupProgress == .completed  {
                    let _: StatusResponse = try send([CancelDeliveryCommand(nonce: podState.currentNonce, deliveryType: .all, beepType: .noBeepCancel)])
                }
            }
            var status: StatusResponse = try send([basalScheduleCommand, basalExtraCommand])
            let now = currentDate
            podState.suspendState = .resumed(now)
            podState.unfinalizedResume = UnfinalizedDose(resumeStartTime: now, scheduledCertainty: .certain, insulinType: podState.insulinType)
            if hasActiveSuspendAlert(configuredAlerts: podState.configuredAlerts),
                let cancelStatus = try? cancelSuspendAlerts()
            {
                status = cancelStatus // update using the latest status
            }
            podState.updateFromStatusResponse(status, at: currentDate)
            return status
        } catch PodCommsError.nonceResyncFailed {
            throw PodCommsError.nonceResyncFailed
        } catch PodCommsError.rejectedMessage(let errorCode) {
            throw PodCommsError.rejectedMessage(errorCode: errorCode)
        } catch let error {
            podState.unfinalizedResume = UnfinalizedDose(resumeStartTime: currentDate, scheduledCertainty: .uncertain, insulinType: podState.insulinType)
            throw error
        }
    }

    public func resumeBasal(schedule: BasalSchedule, scheduleOffset: TimeInterval, acknowledgementBeep: Bool = false, programReminderInterval: TimeInterval = 0) throws -> StatusResponse {

        guard podState.unacknowledgedCommand == nil else {
            throw PodCommsError.unacknowledgedCommandPending
        }


        let status = try setBasalSchedule(schedule: schedule, scheduleOffset: scheduleOffset, acknowledgementBeep: acknowledgementBeep, programReminderInterval: programReminderInterval)

        podState.suspendState = .resumed(currentDate)

        return status
    }

    // use cancelDelivery with .none to get status as well as to validate & advance the nonce
    // Throws PodCommsError
    @discardableResult
    public func cancelNone(beepBlock: MessageBlock? = nil) throws -> StatusResponse {
        var statusResponse: StatusResponse

        let cancelResult: CancelDeliveryResult = cancelDelivery(deliveryType: .none, beepBlock: beepBlock)
        switch cancelResult {
        case .certainFailure(let error):
            throw error
        case .unacknowledged(let error):
            throw error
        case .success(let response, _):
            statusResponse = response
        }
        podState.updateFromStatusResponse(statusResponse, at: currentDate)
        return statusResponse
    }

    // Throws PodCommsError
    @discardableResult
    public func getStatus(beepBlock: MessageBlock? = nil) throws -> StatusResponse {
        let statusResponse: StatusResponse = try send([GetStatusCommand()], beepBlock: beepBlock)

        if podState.unacknowledgedCommand != nil {
            recoverUnacknowledgedCommand(using: statusResponse)
        }
        podState.updateFromStatusResponse(statusResponse, at: currentDate)
        return statusResponse
    }

    @discardableResult
    public func getDetailedStatus(beepBlock: MessageBlock? = nil) throws -> DetailedStatus {
        let infoResponse: PodInfoResponse = try send([GetStatusCommand(podInfoType: .detailedStatus)], beepBlock: beepBlock)

        guard let detailedStatus = infoResponse.podInfo as? DetailedStatus else {
            throw PodCommsError.unexpectedResponse(response: .podInfoResponse)
        }
        if detailedStatus.isFaulted && self.podState.fault == nil {
            // just detected that the pod has faulted, handle setting the fault state but don't throw
            handlePodFault(fault: detailedStatus)
        } else {
            let derivedStatusResponse = StatusResponse(detailedStatus: detailedStatus)
            if podState.unacknowledgedCommand != nil {
                recoverUnacknowledgedCommand(using: derivedStatusResponse)
            }
            podState.updateFromStatusResponse(derivedStatusResponse, at: currentDate)
        }
        return detailedStatus
    }

    @discardableResult
    public func readPodInfo(podInfoResponseSubType: PodInfoResponseSubType, beepBlock: MessageBlock? = nil) throws -> PodInfoResponse {
        let podInfoCommand = GetStatusCommand(podInfoType: podInfoResponseSubType)
        let podInfoResponse: PodInfoResponse = try send([podInfoCommand], beepBlock: beepBlock)
        return podInfoResponse
    }

    // Reconnected to the pod, and we know program was successful
    private func unacknowledgedCommandWasReceived(pendingCommand: PendingCommand, podStatus: StatusResponse) {
        switch pendingCommand {
        case .program(let program, _, let commandDate, _):
            if let dose = program.unfinalizedDose(at: commandDate, withCertainty: .certain, insulinType: podState.insulinType) {
                switch dose.doseType {
                case .bolus:
                    podState.unfinalizedBolus = dose
                case .tempBasal:
                    podState.unfinalizedTempBasal = dose
                case .resume:
                    podState.suspendState = .resumed(commandDate)
                default:
                    break
                }
            }
        case .stopProgram(let stopProgram, _, let commandDate, _):

            if stopProgram.contains(.bolus), let bolus = podState.unfinalizedBolus, !bolus.isFinished(at: commandDate) {
                podState.unfinalizedBolus?.cancel(at: commandDate, withRemaining: podStatus.bolusNotDelivered)
            }
            if stopProgram.contains(.tempBasal), let tempBasal = podState.unfinalizedTempBasal, !tempBasal.isFinished(at: commandDate) {
                podState.unfinalizedTempBasal?.cancel(at: commandDate)
            }
            if stopProgram.contains(.basal) {
                podState.finalizedDoses.append(UnfinalizedDose(suspendStartTime: commandDate, scheduledCertainty: .certain))
                podState.suspendState = .suspended(commandDate)
            }
        }
    }

    public func recoverUnacknowledgedCommand(using status: StatusResponse) {
        if let pendingCommand = podState.unacknowledgedCommand {
            self.log.default("Recovering from unacknowledged command %{public}@, status = %{public}@", String(describing: pendingCommand), String(describing: status))

            if status.lastProgrammingMessageSeqNum == pendingCommand.sequence {
                self.log.default("Unacknowledged command was received by pump")
                unacknowledgedCommandWasReceived(pendingCommand: pendingCommand, podStatus: status)
            } else {
                self.log.default("Unacknowledged command was not received by pump")
            }
            podState.unacknowledgedCommand = nil
        }
    }

    // Can be called a second time to deactivate a given pod
    public func deactivatePod() throws {

        // Don't try to cancel if the pod hasn't completed its setup as it will either receive no response
        // (pod progress state <= 2) or creates a $31 pod fault (pod progress states 3 through 7).
        if podState.setupProgress == .completed && podState.fault == nil && !podState.isSuspended {
            let result = cancelDelivery(deliveryType: .all)
            switch result {
            case .certainFailure(let error):
                throw error
            case .unacknowledged(let error):
                throw error
            default:
                break
            }
        }

        // Try to read the most recent pulse log entries for possible later analysis
        _ = try? readPodInfo(podInfoResponseSubType: .pulseLogRecent)
        if podState.fault != nil {
            // Try to read the previous pulse log entries on the faulted pod
            _ = try? readPodInfo(podInfoResponseSubType: .pulseLogPrevious)
        }

        do {
            let deactivatePod = DeactivatePodCommand(nonce: podState.currentNonce)
            let status: StatusResponse = try send([deactivatePod])

            if podState.unacknowledgedCommand != nil {
                recoverUnacknowledgedCommand(using: status)
            }

            podState.updateFromStatusResponse(status, at: currentDate)

            if podState.activeTime == nil, let activatedAt = podState.activatedAt {
                podState.activeTime = currentDate.timeIntervalSince(activatedAt)
            }
        } catch let error as PodCommsError {
            switch error {
            case .podFault, .activationTimeExceeded, .unexpectedResponse:
                break
            default:
                throw error
            }
        }
    }

    public func acknowledgeAlerts(alerts: AlertSet, beepBlock: MessageBlock? = nil) throws -> AlertSet {
        let cmd = AcknowledgeAlertCommand(nonce: podState.currentNonce, alerts: alerts)
        let status: StatusResponse = try send([cmd], beepBlock: beepBlock)
        podState.updateFromStatusResponse(status, at: currentDate)
        return podState.activeAlertSlots
    }

    func dosesForStorage(_ storageHandler: ([UnfinalizedDose]) -> Bool) {
        assertOnSessionQueue()

        let dosesToStore = podState.dosesToStore

        if storageHandler(dosesToStore) {
            log.info("Stored doses: %@", String(describing: dosesToStore))
            self.podState.finalizedDoses.removeAll()
        }
    }

    public func assertOnSessionQueue() {
        transport.assertOnSessionQueue()
    }
}

extension PodCommsSession: MessageTransportDelegate {
    func messageTransport(_ messageTransport: MessageTransport, didUpdate state: MessageTransportState) {
        messageTransport.assertOnSessionQueue()
        podState.messageTransportState = state
    }
}
