//
//  OmnipodPumpManagerState.swift
//  OmniKit
//
//  Created by Pete Schwamb on 8/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import RileyLinkKit
import RileyLinkBLEKit
import LoopKit


public struct OmnipodPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = PumpManager.RawStateValue
    
    public static let version = 2
    
    public var isOnboarded: Bool

    private (set) public var podState: PodState?

    // podState should only be modifiable by PodComms
    mutating func updatePodStateFromPodComms(_ podState: PodState?) {
        self.podState = podState
    }

    public var pairingAttemptAddress: UInt32?

    public var timeZone: TimeZone
    
    public var basalSchedule: BasalSchedule
    
    public var rileyLinkConnectionManagerState: RileyLinkConnectionState?

    public var unstoredDoses: [UnfinalizedDose]

    public var silencePod: Bool

    public var confirmationBeeps: BeepPreference

    public var scheduledExpirationReminderOffset: TimeInterval?

    public var defaultExpirationReminderOffset = Pod.defaultExpirationReminderOffset

    public var lowReservoirReminderValue: Double

    public var podAttachmentConfirmed: Bool

    public var activeAlerts: Set<PumpManagerAlert>

    public var alertsWithPendingAcknowledgment: Set<PumpManagerAlert>

    public var acknowledgedTimeOffsetAlert: Bool

    // Temporal state not persisted

    internal enum EngageablePumpState: Equatable {
        case engaging
        case disengaging
        case stable
    }

    internal var suspendEngageState: EngageablePumpState = .stable

    internal var bolusEngageState: EngageablePumpState = .stable

    internal var tempBasalEngageState: EngageablePumpState = .stable

    internal var lastPumpDataReportDate: Date?
    
    internal var insulinType: InsulinType?

    // Persistence for the pod state of the previous pod, for
    // user review and manufacturer reporting.
    public var previousPodState: PodState?

    // Indicates that the user has completed initial configuration
    // which means they have configured any parameters, but may not have paired a pod yet.
    public var initialConfigurationCompleted: Bool = false
    
    public var rileyLinkBatteryAlertLevel: Int?
    
    public var lastRileyLinkBatteryAlertDate: Date = .distantPast

    public var maximumTempBasalRate: Double

    // From last status response
    public var reservoirLevel: ReservoirLevel? {
        guard let level = podState?.lastInsulinMeasurements?.reservoirLevel else {
            return nil
        }
        return ReservoirLevel(rawValue: level)
    }

    // MARK: -

    public init(isOnboarded: Bool, podState: PodState?, timeZone: TimeZone, basalSchedule: BasalSchedule, rileyLinkConnectionManagerState: RileyLinkConnectionState?, insulinType: InsulinType?, maximumTempBasalRate: Double) {
        self.isOnboarded = isOnboarded
        self.podState = podState
        self.timeZone = timeZone
        self.basalSchedule = basalSchedule
        self.rileyLinkConnectionManagerState = rileyLinkConnectionManagerState
        self.unstoredDoses = []
        self.silencePod = false
        self.confirmationBeeps = .manualCommands
        self.insulinType = insulinType
        self.lowReservoirReminderValue = Pod.defaultLowReservoirReminder
        self.podAttachmentConfirmed = false
        self.activeAlerts = []
        self.alertsWithPendingAcknowledgment = []
        self.acknowledgedTimeOffsetAlert = false
        self.maximumTempBasalRate = maximumTempBasalRate
    }
    
    public init?(rawValue: RawValue) {
        
        guard let version = rawValue["version"] as? Int else {
            return nil
        }
        
        let basalSchedule: BasalSchedule
        
        if version == 1 {
            // migrate: basalSchedule moved from podState to oppm state
            if let podStateRaw = rawValue["podState"] as? PodState.RawValue,
                let rawBasalSchedule = podStateRaw["basalSchedule"] as? BasalSchedule.RawValue,
                let migrateSchedule = BasalSchedule(rawValue: rawBasalSchedule)
            {
                basalSchedule = migrateSchedule
            } else {
                return nil
            }
        } else {
            guard let rawBasalSchedule = rawValue["basalSchedule"] as? BasalSchedule.RawValue,
                let schedule = BasalSchedule(rawValue: rawBasalSchedule) else
            {
                return nil
            }
            basalSchedule = schedule
        }
        
        let isOnboarded = rawValue["isOnboarded"] as? Bool ?? true // Backward compatibility

        let podState: PodState?
        if let podStateRaw = rawValue["podState"] as? PodState.RawValue {
            podState = PodState(rawValue: podStateRaw)
        } else {
            podState = nil
        }

        let timeZone: TimeZone
        if let timeZoneSeconds = rawValue["timeZone"] as? Int,
            let tz = TimeZone(secondsFromGMT: timeZoneSeconds) {
            timeZone = tz
        } else {
            timeZone = TimeZone.currentFixed
        }
        
        let rileyLinkConnectionManagerState: RileyLinkConnectionState?
        if let rileyLinkConnectionManagerStateRaw = rawValue["rileyLinkConnectionManagerState"] as? RileyLinkConnectionState.RawValue {
            rileyLinkConnectionManagerState = RileyLinkConnectionState(rawValue: rileyLinkConnectionManagerStateRaw)
        } else {
            rileyLinkConnectionManagerState = RileyLinkConnectionState(autoConnectIDs: [])
        }
        
        var insulinType: InsulinType?
        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        }

        // If this doesn't exist (early adopters of dev/pre-3.0) set to zero
        // Will not let them set a manual temp until a limits sync has been performed.
        let maximumTempBasalRate = rawValue["maximumTempBasalRate"] as? Double ?? 0

        self.init(
            isOnboarded: isOnboarded,
            podState: podState,
            timeZone: timeZone,
            basalSchedule: basalSchedule,
            rileyLinkConnectionManagerState: rileyLinkConnectionManagerState,
            insulinType: insulinType ?? .novolog,
            maximumTempBasalRate: maximumTempBasalRate
        )

        if let rawUnstoredDoses = rawValue["unstoredDoses"] as? [UnfinalizedDose.RawValue] {
            self.unstoredDoses = rawUnstoredDoses.compactMap( { UnfinalizedDose(rawValue: $0) } )
        } else {
            self.unstoredDoses = []
        }

        self.silencePod = rawValue["silencePod"] as? Bool ?? false

        if let oldAutomaticBolusBeeps = rawValue["automaticBolusBeeps"] as? Bool, oldAutomaticBolusBeeps {
            self.confirmationBeeps = .extended
        } else if let oldConfirmationBeeps = rawValue["confirmationBeeps"] as? Bool, oldConfirmationBeeps {
            self.confirmationBeeps = .manualCommands
        } else {
            if let rawBeeps = rawValue["confirmationBeeps"] as? BeepPreference.RawValue, let confirmationBeeps = BeepPreference(rawValue: rawBeeps) {
                self.confirmationBeeps = confirmationBeeps
            } else {
                self.confirmationBeeps = .manualCommands
            }
        }

        self.scheduledExpirationReminderOffset = rawValue["scheduledExpirationReminderOffset"] as? TimeInterval

        self.defaultExpirationReminderOffset = rawValue["defaultExpirationReminderOffset"] as? TimeInterval ?? Pod.defaultExpirationReminderOffset

        self.lowReservoirReminderValue = rawValue["lowReservoirReminderValue"] as? Double ?? Pod.defaultLowReservoirReminder

        self.podAttachmentConfirmed = rawValue["podAttachmentConfirmed"] as? Bool ?? false

        self.initialConfigurationCompleted = rawValue["initialConfigurationCompleted"] as? Bool ?? true

        self.acknowledgedTimeOffsetAlert = rawValue["acknowledgedTimeOffsetAlert"] as? Bool ?? false

        if let lastPumpDataReportDate = rawValue["lastPumpDataReportDate"] as? Date {
            self.lastPumpDataReportDate = lastPumpDataReportDate
        }

        if let pairingAttemptAddress = rawValue["pairingAttemptAddress"] as? UInt32 {
            self.pairingAttemptAddress = pairingAttemptAddress
        }
        
        rileyLinkBatteryAlertLevel = rawValue["rileyLinkBatteryAlertLevel"] as? Int
        lastRileyLinkBatteryAlertDate = rawValue["lastRileyLinkBatteryAlertDate"] as? Date ?? Date.distantPast

        self.activeAlerts = []
        if let rawActiveAlerts = rawValue["activeAlerts"] as? [PumpManagerAlert.RawValue] {
            for rawAlert in rawActiveAlerts {
                if let alert = PumpManagerAlert(rawValue: rawAlert) {
                    self.activeAlerts.insert(alert)
                }
            }
        }

        self.alertsWithPendingAcknowledgment = []
        if let rawAlerts = rawValue["alertsWithPendingAcknowledgment"] as? [PumpManagerAlert.RawValue] {
            for rawAlert in rawAlerts {
                if let alert = PumpManagerAlert(rawValue: rawAlert) {
                    self.alertsWithPendingAcknowledgment.insert(alert)
                }
            }
        }

        if let prevPodStateRaw = rawValue["previousPodState"] as? PodState.RawValue {
            previousPodState = PodState(rawValue: prevPodStateRaw)
        } else {
            previousPodState = nil
        }
    }
    
    public var rawValue: RawValue {
        var value: [String : Any] = [
            "version": OmnipodPumpManagerState.version,
            "isOnboarded": isOnboarded,
            "timeZone": timeZone.secondsFromGMT(),
            "basalSchedule": basalSchedule.rawValue,
            "unstoredDoses": unstoredDoses.map { $0.rawValue },
            "silencePod": silencePod,
            "confirmationBeeps": confirmationBeeps.rawValue,
            "activeAlerts": activeAlerts.map { $0.rawValue },
            "podAttachmentConfirmed": podAttachmentConfirmed,
            "acknowledgedTimeOffsetAlert": acknowledgedTimeOffsetAlert,
            "alertsWithPendingAcknowledgment": alertsWithPendingAcknowledgment.map { $0.rawValue },
            "initialConfigurationCompleted": initialConfigurationCompleted,
            "maximumTempBasalRate": maximumTempBasalRate
        ]
        
        value["insulinType"] = insulinType?.rawValue
        value["podState"] = podState?.rawValue
        value["scheduledExpirationReminderOffset"] = scheduledExpirationReminderOffset
        value["defaultExpirationReminderOffset"] = defaultExpirationReminderOffset
        value["lowReservoirReminderValue"] = lowReservoirReminderValue
        value["rileyLinkConnectionManagerState"] = rileyLinkConnectionManagerState?.rawValue
        value["pairingAttemptAddress"] = pairingAttemptAddress
        value["rileyLinkBatteryAlertLevel"] = rileyLinkBatteryAlertLevel
        value["lastRileyLinkBatteryAlertDate"] = lastRileyLinkBatteryAlertDate
        value["lastPumpDataReportDate"] = lastPumpDataReportDate
        value["previousPodState"] = previousPodState?.rawValue
        
        return value
    }
}

extension OmnipodPumpManagerState {
    var hasActivePod: Bool {
        return podState?.isActive == true
    }

    var hasSetupPod: Bool {
        return podState?.isSetupComplete == true
    }

    var isPumpDataStale: Bool {
        let pumpStatusAgeTolerance = TimeInterval(minutes: 6)
        let pumpDataAge = -(self.lastPumpDataReportDate ?? .distantPast).timeIntervalSinceNow
        return pumpDataAge > pumpStatusAgeTolerance
    }
}


extension OmnipodPumpManagerState: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## OmnipodPumpManagerState",
            "* isOnboarded: \(isOnboarded)",
            "* timeZone: \(timeZone)",
            "* basalSchedule: \(String(describing: basalSchedule))",
            "* maximumTempBasalRate: \(maximumTempBasalRate)",
            "* scheduledExpirationReminderOffset: \(String(describing: scheduledExpirationReminderOffset?.timeIntervalStr))",
            "* defaultExpirationReminderOffset: \(defaultExpirationReminderOffset.timeIntervalStr)",
            "* lowReservoirReminderValue: \(String(describing: lowReservoirReminderValue))",
            "* podAttachmentConfirmed: \(podAttachmentConfirmed)",
            "* activeAlerts: \(activeAlerts)",
            "* alertsWithPendingAcknowledgment: \(alertsWithPendingAcknowledgment)",
            "* acknowledgedTimeOffsetAlert: \(acknowledgedTimeOffsetAlert)",
            "* initialConfigurationCompleted: \(initialConfigurationCompleted)",
            "* unstoredDoses: \(String(describing: unstoredDoses))",
            "* suspendEngageState: \(String(describing: suspendEngageState))",
            "* bolusEngageState: \(String(describing: bolusEngageState))",
            "* tempBasalEngageState: \(String(describing: tempBasalEngageState))",
            "* lastPumpDataReportDate: \(String(describing: lastPumpDataReportDate))",
            "* isPumpDataStale: \(String(describing: isPumpDataStale))",
            "* silencePod: \(String(describing: silencePod))",
            "* confirmationBeeps: \(String(describing: confirmationBeeps))",
            "* pairingAttemptAddress: \(String(describing: pairingAttemptAddress))",
            "* insulinType: \(String(describing: insulinType))",
            "* scheduledExpirationReminderOffset: \(String(describing: scheduledExpirationReminderOffset?.timeIntervalStr))",
            "* defaultExpirationReminderOffset: \(defaultExpirationReminderOffset.timeIntervalStr)",
            "* rileyLinkBatteryAlertLevel: \(String(describing: rileyLinkBatteryAlertLevel))",
            "* lastRileyLinkBatteryAlertDate \(String(describing: lastRileyLinkBatteryAlertDate))",
            "",
            "* RileyLinkConnectionManagerState: " + (rileyLinkConnectionManagerState == nil ? "nil" : String(describing: rileyLinkConnectionManagerState!)),
            "",
            "* PodState: " + (podState == nil ? "nil" : String(describing: podState!)),
            "",
            "* PreviousPodState: " + (previousPodState == nil ? "nil" : String(describing: previousPodState!)),
            "",
        ].joined(separator: "\n")
    }
}
