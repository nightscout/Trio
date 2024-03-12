//
//  PodState.swift
//  OmnipodKit
//
//  Based on OmniKit/PumpManager/PodState.swift
//  Created by Pete Schwamb on 10/13/17.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public enum SetupProgress: Int {
    case addressAssigned = 0
    case podPaired
    case startingPrime
    case priming
    case settingInitialBasalSchedule
    case initialBasalScheduleSet
    case startingInsertCannula
    case cannulaInserting
    case completed
    case activationTimeout
    case podIncompatible

    public var isPaired: Bool {
        return self.rawValue >= SetupProgress.podPaired.rawValue
    }

    public var primingNeverAttempted: Bool {
        return self.rawValue < SetupProgress.startingPrime.rawValue
    }
    
    public var primingNeeded: Bool {
        return self.rawValue < SetupProgress.priming.rawValue
    }
    
    public var needsInitialBasalSchedule: Bool {
        return self.rawValue < SetupProgress.initialBasalScheduleSet.rawValue
    }

    public var needsCannulaInsertion: Bool {
        return self.rawValue < SetupProgress.completed.rawValue
    }
}

// TODO: Mutating functions aren't guaranteed to synchronize read/write calls.
// mutating funcs should be moved to something like this:
// extension Locked where T == PodState {
// }
public struct PodState: RawRepresentable, Equatable, CustomDebugStringConvertible {
    
    public typealias RawValue = [String: Any]
    
    public let address: UInt32
    public let ltk: Data
     
    public var bleIdentifier: String
    
    public var activatedAt: Date?
    public var expiresAt: Date?  // set based on StatusResponse timeActive and can change with Pod clock drift and/or system time change
    public var activeTime: TimeInterval? // Useful after pod deactivated or faulted.

    public var setupUnitsDelivered: Double?

    public let firmwareVersion: String
    public let bleFirmwareVersion: String
    public let lotNo: UInt32
    public let lotSeq: UInt32
    public let productId: UInt8
    var activeAlertSlots: AlertSet
    public var lastInsulinMeasurements: PodInsulinMeasurements?

    public var unacknowledgedCommand: PendingCommand?

    public var unfinalizedBolus: UnfinalizedDose?
    public var unfinalizedTempBasal: UnfinalizedDose?
    public var unfinalizedSuspend: UnfinalizedDose?
    public var unfinalizedResume: UnfinalizedDose?

    var finalizedDoses: [UnfinalizedDose]

    public var dosesToStore: [UnfinalizedDose] {
        return  finalizedDoses + [unfinalizedTempBasal, unfinalizedSuspend, unfinalizedBolus].compactMap {$0}
    }

    public var suspendState: SuspendState

    public var isSuspended: Bool {
        if case .suspended = suspendState {
            return true
        }
        return false
    }

    public var fault: DetailedStatus?
    public var messageTransportState: MessageTransportState
    public var primeFinishTime: Date?
    public var setupProgress: SetupProgress
    public var configuredAlerts: [AlertSlot: PodAlert]
    public var insulinType: InsulinType

    public var activeAlerts: [AlertSlot: PodAlert] {
        var active = [AlertSlot: PodAlert]()
        for slot in activeAlertSlots {
            if let alert = configuredAlerts[slot] {
                active[slot] = alert
            }
        }
        return active
    }

    // Allow a grace period while the unacknowledged command is first being sent.
    public var needsCommsRecovery: Bool {
        if let unacknowledgedCommand = unacknowledgedCommand, !unacknowledgedCommand.isInFlight {
            return true
        }
        return false
    }
    
    public init(address: UInt32, ltk: Data, firmwareVersion: String, bleFirmwareVersion: String, lotNo: UInt32, lotSeq: UInt32, productId: UInt8, messageTransportState: MessageTransportState? = nil, bleIdentifier: String, insulinType: InsulinType) {
        self.address = address
        self.ltk = ltk
        self.firmwareVersion = firmwareVersion
        self.bleFirmwareVersion = bleFirmwareVersion
        self.lotNo = lotNo
        self.lotSeq = lotSeq
        self.productId = productId
        self.lastInsulinMeasurements = nil
        self.finalizedDoses = []
        self.suspendState = .resumed(Date())
        self.fault = nil
        self.activeAlertSlots = .none
        self.messageTransportState = messageTransportState ?? MessageTransportState(ck: nil, noncePrefix: nil)
        self.primeFinishTime = nil
        self.setupProgress = .addressAssigned
        self.configuredAlerts = [.slot7: .waitingForPairingReminder]
        self.bleIdentifier = bleIdentifier
        self.insulinType = insulinType
    }
    
    public var unfinishedSetup: Bool {
        return setupProgress != .completed
    }
    
    public var readyForCannulaInsertion: Bool {
        guard let primeFinishTime = self.primeFinishTime else {
            return false
        }
        return !setupProgress.primingNeeded && primeFinishTime.timeIntervalSinceNow < 0
    }

    public var isActive: Bool {
        return setupProgress == .completed && fault == nil
    }

    // variation on isActive that doesn't care if Pod is faulted
    public var isSetupComplete: Bool {
        return setupProgress == .completed
    }

    public var isFaulted: Bool {
        return fault != nil || setupProgress == .activationTimeout || setupProgress == .podIncompatible
    }
    
    public mutating func incrementEapSeq() -> Int {
        self.messageTransportState.eapSeq += 1
        return messageTransportState.eapSeq
    }

    public mutating func advanceToNextNonce() {
        // Dash nonce is a fixed value and is never advanced
    }
    
    public var currentNonce: UInt32 {
        let fixedNonceValue: UInt32 = 0x494E532E // Dash uses a fixed value for pod nonce
        return fixedNonceValue // not clear if the actual value even matters
    }
    
    public mutating func resyncNonce(syncWord: UInt16, sentNonce: UInt32, messageSequenceNum: Int) {
        assert(false) // XXX ?should never be called for Dash?
    }
    
    private mutating func updatePodTimes(timeActive: TimeInterval) -> Date {
        let now = Date()
        let activatedAtComputed = now - timeActive
        if activatedAt == nil {
            self.activatedAt = activatedAtComputed
        }
        let expiresAtComputed = activatedAtComputed + Pod.nominalPodLife
        if expiresAt == nil {
            self.expiresAt = expiresAtComputed
        } else if expiresAtComputed < self.expiresAt! || expiresAtComputed > (self.expiresAt! + TimeInterval(minutes: 1)) {
            // The computed expiresAt time is earlier than or more than a minute later than the current expiresAt time,
            // so use the computed expiresAt time instead to handle Pod clock drift and/or system time changes issues.
            // The more than a minute later test prevents oscillation of expiresAt based on the timing of the responses.
            // TODO: A significant deviation expiresAt from activatedAt + nominalPodLife should generate a critical alert
            self.expiresAt = expiresAtComputed
        }
        return now
    }

    public mutating func updateFromStatusResponse(_ response: StatusResponse, at date: Date = Date()) {
        let now = updatePodTimes(timeActive: response.timeActive)
        updateDeliveryStatus(deliveryStatus: response.deliveryStatus, podProgressStatus: response.podProgressStatus, bolusNotDelivered: response.bolusNotDelivered, at: date)

        let setupUnits = setupUnitsDelivered ?? Pod.primeUnits + Pod.cannulaInsertionUnits + Pod.cannulaInsertionUnitsExtra

        // Calculated new delivered value which will be a negative value until setup has completed OR after a pod reset fault
        let calcDelivered = response.insulinDelivered - setupUnits

        // insulinDelivered should never be a negative value or decrease from the previous saved delivered value
        let prevDelivered = lastInsulinMeasurements?.delivered ?? 0
        let insulinDelivered = max(calcDelivered, prevDelivered)

        lastInsulinMeasurements = PodInsulinMeasurements(insulinDelivered: insulinDelivered, reservoirLevel: response.reservoirLevel, validTime: now)

        activeAlertSlots = response.alerts
    }

    public mutating func registerConfiguredAlert(slot: AlertSlot, alert: PodAlert) {
        configuredAlerts[slot] = alert
    }

    public mutating func finalizeAllDoses() {
        if let bolus = unfinalizedBolus {
            finalizedDoses.append(bolus)
            unfinalizedBolus = nil
        }

        if let tempBasal = unfinalizedTempBasal {
            finalizedDoses.append(tempBasal)
            unfinalizedTempBasal = nil
        }
    }

    // Giving up on pod; we will assume commands failed/succeeded in the direction of positive net delivery
    mutating func resolveAnyPendingCommandWithUncertainty() {
        guard let pendingCommand = unacknowledgedCommand else {
            return
        }

        switch pendingCommand {
        case .program(let program, _, let commandDate, _):

            if let dose = program.unfinalizedDose(at: commandDate, withCertainty: .uncertain, insulinType: insulinType) {
                switch dose.doseType {
                case .bolus:
                    if dose.isFinished() {
                        finalizedDoses.append(dose)
                    } else {
                        unfinalizedBolus = dose
                    }
                case .tempBasal:
                    // Assume a high temp succeeded, but low temp failed
                    if case .tempBasal(_, _, let isHighTemp, _) = program, isHighTemp {
                        if dose.isFinished() {
                            finalizedDoses.append(dose)
                        } else {
                            unfinalizedTempBasal = dose
                        }
                    }
                case .resume:
                    finalizedDoses.append(dose)
                case .suspend:
                    break // start program is never a suspend
                }
            }
        case .stopProgram(let stopProgram, _, let commandDate, _):
            // All stop programs result in reduced delivery, except for stopping a low temp, so we assume all stop
            // commands failed, except for low temp
            

            if stopProgram.contains(.tempBasal),
                let tempBasal = unfinalizedTempBasal,
                tempBasal.isHighTemp,
                !tempBasal.isFinished(at: commandDate)
            {
                unfinalizedTempBasal?.cancel(at: commandDate)
            }
        }
        self.unacknowledgedCommand = nil
    }

    
    private mutating func updateDeliveryStatus(deliveryStatus: DeliveryStatus, podProgressStatus: PodProgressStatus, bolusNotDelivered: Double, at date: Date) {

        // See if the pod deliveryStatus indicates an active bolus or temp basal that the PodState isn't tracking (possible Loop restart)
        if deliveryStatus.bolusing && unfinalizedBolus == nil { // active bolus that Loop doesn't know about?
            if podProgressStatus.readyForDelivery {
                // Create an unfinalizedBolus with the remaining bolus amount to capture what we can.
                unfinalizedBolus = UnfinalizedDose(bolusAmount: bolusNotDelivered, startTime: date, scheduledCertainty: .certain, insulinType: insulinType, automatic: false)
            }
        }

        if var bolus = unfinalizedBolus, !deliveryStatus.bolusing {
            // Due to clock drift or comms delays, boluses can finish earlier than we expect
            if !bolus.isFinished() {
                bolus.finishTime = date
            }
            finalizedDoses.append(bolus)
            unfinalizedBolus = nil
        }

        if var tempBasal = unfinalizedTempBasal, !deliveryStatus.tempBasalRunning {
            if !tempBasal.isFinished() {
                tempBasal.finishTime = date
            }
            finalizedDoses.append(tempBasal)
            unfinalizedTempBasal = nil
        }

        if let suspend = unfinalizedSuspend {

            if let resume = unfinalizedResume, suspend.startTime < resume.startTime {
                finalizedDoses.append(suspend)
                finalizedDoses.append(resume)
                unfinalizedSuspend = nil
                unfinalizedResume = nil
            }
        }
    }

    // MARK: - RawRepresentable
    public init?(rawValue: RawValue) {

        guard
            let address = rawValue["address"] as? UInt32,
            let ltkString = rawValue["ltk"] as? String,
            let firmwareVersion = rawValue["firmwareVersion"] as? String,
            let bleFirmwareVersion = rawValue["bleFirmwareVersion"] as? String,
            let bleIdentifier = rawValue["bleIdentifier"] as? String,
            let lotNo = rawValue["lotNo"] as? UInt32,
            let lotSeq = rawValue["lotSeq"] as? UInt32
            else {
                return nil
            }
        
        let formatVersion: Int = rawValue["version"] as? Int ?? 1
        
        self.address = address
        self.ltk = Data(hex: ltkString)
        self.firmwareVersion = firmwareVersion
        self.bleFirmwareVersion = bleFirmwareVersion
        self.lotNo = lotNo
        self.lotSeq = lotSeq
        if let productId = rawValue["productId"] as? UInt8 {
            self.productId = productId
        } else {
            self.productId = dashProductId
        }
        self.bleIdentifier = bleIdentifier

        self.activeTime = rawValue["activeTime"] as? TimeInterval

        if let activatedAt = rawValue["activatedAt"] as? Date {
            self.activatedAt = activatedAt
            if let expiresAt = rawValue["expiresAt"] as? Date {
                self.expiresAt = expiresAt
            } else {
                self.expiresAt = activatedAt + Pod.nominalPodLife
            }
        }

        if let setupUnitsDelivered = rawValue["setupUnitsDelivered"] as? Double {
            self.setupUnitsDelivered = setupUnitsDelivered
        }

        if let suspended = rawValue["suspended"] as? Bool {
            // Migrate old value
            if suspended {
                suspendState = .suspended(Date())
            } else {
                suspendState = .resumed(Date())
            }
        } else if let rawSuspendState = rawValue["suspendState"] as? SuspendState.RawValue, let suspendState = SuspendState(rawValue: rawSuspendState) {
            self.suspendState = suspendState
        } else {
            return nil
        }

        if let rawPendingCommand = rawValue["unacknowledgedCommand"] as? PendingCommand.RawValue {
            // When loading from raw state, we know comms are no longer in progress; this helps recover from a crash
            self.unacknowledgedCommand = PendingCommand(rawValue: rawPendingCommand)?.commsFinished
        } else {
            self.unacknowledgedCommand = nil
        }

        if let rawUnfinalizedBolus = rawValue["unfinalizedBolus"] as? UnfinalizedDose.RawValue
        {
            self.unfinalizedBolus = UnfinalizedDose(rawValue: rawUnfinalizedBolus)
        }

        if let rawUnfinalizedTempBasal = rawValue["unfinalizedTempBasal"] as? UnfinalizedDose.RawValue
        {
            self.unfinalizedTempBasal = UnfinalizedDose(rawValue: rawUnfinalizedTempBasal)
        }

        if let rawUnfinalizedSuspend = rawValue["unfinalizedSuspend"] as? UnfinalizedDose.RawValue
        {
            self.unfinalizedSuspend = UnfinalizedDose(rawValue: rawUnfinalizedSuspend)
        }

        if let rawUnfinalizedResume = rawValue["unfinalizedResume"] as? UnfinalizedDose.RawValue
        {
            self.unfinalizedResume = UnfinalizedDose(rawValue: rawUnfinalizedResume)
        }

        if let rawLastInsulinMeasurements = rawValue["lastInsulinMeasurements"] as? PodInsulinMeasurements.RawValue {
            self.lastInsulinMeasurements = PodInsulinMeasurements(rawValue: rawLastInsulinMeasurements)
        } else {
            self.lastInsulinMeasurements = nil
        }
        
        if let rawFinalizedDoses = rawValue["finalizedDoses"] as? [UnfinalizedDose.RawValue] {
            self.finalizedDoses = rawFinalizedDoses.compactMap( { UnfinalizedDose(rawValue: $0) } )
        } else {
            self.finalizedDoses = []
        }

        if let rawFault = rawValue["fault"] as? DetailedStatus.RawValue,
           let fault = DetailedStatus(rawValue: rawFault),
           fault.faultEventCode.faultType != .noFaults
        {
            self.fault = fault
        } else {
            self.fault = nil
        }
        
        if let alarmsRawValue = rawValue["alerts"] as? UInt8 {
            self.activeAlertSlots = AlertSet(rawValue: alarmsRawValue)
        } else {
            self.activeAlertSlots = .none
        }
        
        if let setupProgressRaw = rawValue["setupProgress"] as? Int,
            let setupProgress = SetupProgress(rawValue: setupProgressRaw)
        {
            self.setupProgress = setupProgress
        } else {
            // Migrate
            self.setupProgress = .completed
        }
        
        if let messageTransportStateRaw = rawValue["messageTransportState"] as? MessageTransportState.RawValue,
            let messageTransportState = MessageTransportState(rawValue: messageTransportStateRaw)
        {
            self.messageTransportState = messageTransportState
        } else {
            self.messageTransportState = MessageTransportState(ck: nil, noncePrefix: nil)
        }
        
        if let rawConfiguredAlerts = rawValue["configuredAlerts"] as? [String: PodAlert.RawValue], formatVersion >= 2 {
            var configuredAlerts = [AlertSlot: PodAlert]()
            for (rawSlot, rawAlert) in rawConfiguredAlerts {
                if let slotNum = UInt8(rawSlot), let slot = AlertSlot(rawValue: slotNum), let alert = PodAlert(rawValue: rawAlert) {
                    configuredAlerts[slot] = alert
                }
            }
            self.configuredAlerts = configuredAlerts
        } else {
            // Assume migration, and set up with alerts that are normally configured
            self.configuredAlerts = [
                .slot2: .shutdownImminent(0),
                .slot3: .expirationReminder(0),
                .slot4: .lowReservoir(0),
                .slot5: .podSuspendedReminder(active: false, suspendTime: 0),
                .slot6: .suspendTimeExpired(suspendTime: 0),
                .slot7: .expired(alertTime: 0, duration: 0)
            ]
        }
        
        self.primeFinishTime = rawValue["primeFinishTime"] as? Date

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue, let insulinType = InsulinType(rawValue: rawInsulinType) {
            self.insulinType = insulinType
        } else {
            self.insulinType = .novolog
        }
    }
    
    public var rawValue: RawValue {
        var rawValue: RawValue = [
            "version": 2, // Version of encoding format. 1 = old alert names
            "address": address,
            "ltk": ltk.hexadecimalString,
            "eapAkaSequenceNumber": 1, // keep for back migration, was always 1
            "firmwareVersion": firmwareVersion,
            "bleFirmwareVersion": bleFirmwareVersion,
            "lotNo": lotNo,
            "lotSeq": lotSeq,
            "suspendState": suspendState.rawValue,
            "finalizedDoses": finalizedDoses.map( { $0.rawValue }),
            "alerts": activeAlertSlots.rawValue,
            "messageTransportState": messageTransportState.rawValue,
            "setupProgress": setupProgress.rawValue,
            "bleIdentifier": bleIdentifier,
            "insulinType": insulinType.rawValue
            ]

        rawValue["unacknowledgedCommand"] = unacknowledgedCommand?.rawValue
        rawValue["unfinalizedBolus"] = unfinalizedBolus?.rawValue
        rawValue["unfinalizedTempBasal"] = unfinalizedTempBasal?.rawValue
        rawValue["unfinalizedSuspend"] = unfinalizedSuspend?.rawValue
        rawValue["unfinalizedResume"] = unfinalizedResume?.rawValue
        rawValue["lastInsulinMeasurements"] = lastInsulinMeasurements?.rawValue
        rawValue["fault"] = fault?.rawValue
        rawValue["primeFinishTime"] = primeFinishTime
        rawValue["activatedAt"] = activatedAt
        rawValue["expiresAt"] = expiresAt
        rawValue["setupUnitsDelivered"] = setupUnitsDelivered
        rawValue["activeTime"] = activeTime

        if configuredAlerts.count > 0 {
            let rawConfiguredAlerts = Dictionary(uniqueKeysWithValues:
                configuredAlerts.map { slot, alarm in (String(describing: slot.rawValue), alarm.rawValue) })
            rawValue["configuredAlerts"] = rawConfiguredAlerts
        }

        return rawValue
    }
    
    // MARK: - CustomDebugStringConvertible
    
    public var debugDescription: String {
        return [
            "### PodState",
            "* address: \(String(format: "%08X", address))",
            "* bleIdentifier: \(bleIdentifier)",
            "* activatedAt: \(String(reflecting: activatedAt))",
            "* expiresAt: \(String(reflecting: expiresAt))",
            "* setupUnitsDelivered: \(String(reflecting: setupUnitsDelivered))",
            "* firmwareVersion: \(firmwareVersion)",
            "* bleFirmwareVersion: \(bleFirmwareVersion)",
            "* lotNo: \(lotNo)",
            "* lotSeq: \(lotSeq)",
            "* suspendState: \(suspendState)",
            "* unacknowledgedCommand: \(String(describing: unacknowledgedCommand))",
            "* unfinalizedBolus: \(String(describing: unfinalizedBolus))",
            "* unfinalizedTempBasal: \(String(describing: unfinalizedTempBasal))",
            "* unfinalizedSuspend: \(String(describing: unfinalizedSuspend))",
            "* unfinalizedResume: \(String(describing: unfinalizedResume))",
            "* finalizedDoses: \(String(describing: finalizedDoses))",
            "* activeAlerts: \(String(describing: activeAlerts))",
            "* messageTransportState: \(String(describing: messageTransportState))",
            "* setupProgress: \(setupProgress)",
            "* primeFinishTime: \(String(describing: primeFinishTime))",
            "* configuredAlerts: \(String(describing: configuredAlerts))",
            "* insulinType: \(String(describing: insulinType))",
            "* pdmRef: \(String(describing: fault?.pdmRef))",
            "",
            fault != nil ? String(reflecting: fault!) : "fault: nil",
            "",
        ].joined(separator: "\n")
    }
}

public enum SuspendState: Equatable, RawRepresentable {
    public typealias RawValue = [String: Any]

    private enum SuspendStateType: Int {
        case suspend, resume
    }

    case suspended(Date)
    case resumed(Date)

    private var identifier: Int {
        switch self {
        case .suspended:
            return 1
        case .resumed:
            return 2
        }
    }

    public init?(rawValue: RawValue) {
        guard let suspendStateType = rawValue["case"] as? SuspendStateType.RawValue,
            let date = rawValue["date"] as? Date else {
                return nil
        }
        switch SuspendStateType(rawValue: suspendStateType) {
        case .suspend?:
            self = .suspended(date)
        case .resume?:
            self = .resumed(date)
        default:
            return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .suspended(let date):
            return [
                "case": SuspendStateType.suspend.rawValue,
                "date": date
            ]
        case .resumed(let date):
            return [
                "case": SuspendStateType.resume.rawValue,
                "date": date
            ]
        }
    }
}
