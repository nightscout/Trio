//
//  Alert.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/24/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

fileprivate let defaultShutdownImminentTime = Pod.serviceDuration - Pod.endOfServiceImminentWindow
fileprivate let defaultExpirationReminderTime = Pod.nominalPodLife - Pod.defaultExpirationReminderOffset
fileprivate let defaultExpiredTime = Pod.nominalPodLife

// PDM and pre-SwiftUI use every1MinuteFor3MinutesAndRepeatEvery15Minutes, but with SwiftUI use every15Minutes
fileprivate let suspendTimeExpiredBeepRepeat = BeepRepeat.every15Minutes

public enum AlertTrigger {
    case unitsRemaining(Double)
    case timeUntilAlert(TimeInterval)
}

extension AlertTrigger: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .unitsRemaining(let units):
            return "\(Int(units))U"
        case .timeUntilAlert(let triggerTime):
            return "triggerTime=\(triggerTime.timeIntervalStr)"
        }
    }
}

public enum BeepRepeat: UInt8 {
    case once = 0
    case every1MinuteFor3MinutesAndRepeatEvery60Minutes = 1
    case every1MinuteFor15Minutes = 2
    case every1MinuteFor3MinutesAndRepeatEvery15Minutes = 3
    case every3MinutesFor60minutesStartingAt2Minutes = 4
    case every60Minutes = 5
    case every15Minutes = 6
    case every15MinutesFor60minutesStartingAt14Minutes = 7
    case every5Minutes = 8
}


public struct AlertConfiguration {

    let slot: AlertSlot
    let active: Bool
    let duration: TimeInterval
    let trigger: AlertTrigger
    let beepRepeat: BeepRepeat
    let beepType: BeepType
    let silent: Bool
    let autoOffModifier: Bool

    static let length = 6

    public init(alertType: AlertSlot, active: Bool = true, duration: TimeInterval = 0, trigger: AlertTrigger, beepRepeat: BeepRepeat, beepType: BeepType, silent: Bool = false, autoOffModifier: Bool = false)
    {
        self.slot = alertType
        self.active = active
        self.duration = duration
        self.trigger = trigger
        self.beepRepeat = beepRepeat
        self.beepType = beepType
        self.silent = silent
        self.autoOffModifier = autoOffModifier
    }
}

extension AlertConfiguration: CustomDebugStringConvertible {
    public var debugDescription: String {
        var str = "slot:\(slot)"
        if !active {
            str += ", active:\(active)"
        }
        if duration != 0 {
            str += ", duration:\(duration.timeIntervalStr)"
        }
        str += ", trigger:\(trigger), beepRepeat:\(beepRepeat)"
        if beepType != .noBeepNonCancel {
            str += ", beepType:\(beepType)"
        } else {
            str += ", silent:\(silent)"
        }
        if autoOffModifier {
            str += ", autoOffModifier:\(autoOffModifier)"
        }
        return "\nAlertConfiguration(\(str))"
    }
}



public enum PodAlert: CustomStringConvertible, RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    // slot0AutoOff: auto-off timer; requires user input every x minutes -- NOT IMPLEMENTED
    case autoOff(active: Bool, offset: TimeInterval, countdownDuration: TimeInterval, silent: Bool = false)

    // slot1NotUsed
    case notUsed

    // slot2ShutdownImminent: 79 hour alarm (1 hour before shutdown)
    // 2 sets of beeps every 15 minutes for 1 hour
    case shutdownImminent(offset: TimeInterval, absAlertTime: TimeInterval, silent: Bool = false)

    // slot3ExpirationReminder: User configurable with PDM (1-24 hours before 72 hour expiration)
    // 2 sets of beeps every minute for 3 minutes and repeat every 15 minutes
    // The PDM doesn't use a duration for this alert (presumably because it is limited to 2^9-1 minutes or 8h31m)
    case expirationReminder(offset: TimeInterval, absAlertTime: TimeInterval, duration: TimeInterval = 0, silent: Bool = false)

    // slot4LowReservoir: reservoir below configured value alert
    case lowReservoir(units: Double, silent: Bool = false)

    // slot5SuspendedReminder: pod suspended reminder, before suspendTime;
    // short beep every 15 minutes if > 30 min, else short beep every 5 minutes
    case podSuspendedReminder(active: Bool, offset: TimeInterval, suspendTime: TimeInterval, timePassed: TimeInterval = 0, silent: Bool = false)

    // slot6SuspendTimeExpired: pod suspend time expired alarm, after suspendTime;
    // 2 sets of beeps every minute for 3 minutes repeated every 15 minutes (PDM & pre-SwiftUI implementations)
    // 2 sets of beeps every 15 minutes (for SwiftUI PumpManagerAlerts implementations)
    case suspendTimeExpired(offset: TimeInterval, suspendTime: TimeInterval, silent: Bool = false)

    // slot7Expired: 2 hours long, time for user to start pairing process
    case waitingForPairingReminder

    // slot7Expired: 1 hour long, time for user to finish priming, cannula insertion
    case finishSetupReminder

    // slot7Expired: 72 hour alarm
    case expired(offset: TimeInterval, absAlertTime: TimeInterval, duration: TimeInterval, silent: Bool = false)

    public var description: String {
        var alertName: String
        switch self {
        // slot0AutoOff
        case .autoOff:
            alertName = LocalizedString("Auto-off", comment: "Description for auto-off alert")
        // slot1NotUsed
        case .notUsed:
            alertName = LocalizedString("Not used", comment: "Description for not used slot alert")
        // slot2ShutdownImminent
        case .shutdownImminent:
            alertName = LocalizedString("Shutdown imminent", comment: "Description for shutdown imminent alert")
        // slot3ExpirationReminder
        case .expirationReminder:
            alertName = LocalizedString("Expiration reminder", comment: "Description for expiration reminder alert")
        // slot4LowReservoir
        case .lowReservoir:
            alertName = LocalizedString("Low reservoir", comment: "Format string for description for low reservoir alert")
        // slot5SuspendedReminder
        case .podSuspendedReminder:
            alertName = LocalizedString("Pod suspended reminder", comment: "Description for pod suspended reminder alert")
        // slot6SuspendTimeExpired
        case .suspendTimeExpired:
            alertName = LocalizedString("Suspend time expired", comment: "Description for suspend time expired alert")
        // slot7Expired
        case .waitingForPairingReminder:
            alertName = LocalizedString("Waiting for pairing reminder", comment: "Description waiting for pairing reminder alert")
        case .finishSetupReminder:
            alertName = LocalizedString("Finish setup reminder", comment: "Description for finish setup reminder alert")
        case .expired:
            alertName = LocalizedString("Pod expired", comment: "Description for pod expired alert")
        }
        if self.configuration.active == false {
            alertName += LocalizedString(" (inactive)", comment: "Description for an inactive alert modifier")
        }
        return alertName
    }

    public var configuration: AlertConfiguration {
        switch self {
        // slot0AutoOff
        case .autoOff(let active, _, let countdownDuration, let silent):
            return AlertConfiguration(alertType: .slot0AutoOff, active: active, duration: .minutes(15), trigger: .timeUntilAlert(countdownDuration), beepRepeat: .every1MinuteFor15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep, silent: silent, autoOffModifier: true)

        // slot1NotUsed
        case .notUsed:
            return AlertConfiguration(alertType: .slot1NotUsed, duration: .minutes(55), trigger: .timeUntilAlert(.minutes(5)), beepRepeat: .every5Minutes, beepType: .noBeepNonCancel)

        // slot2ShutdownImminent
        case .shutdownImminent(let offset, let absAlertTime, let silent):
            let active = absAlertTime != 0 // disable if absAlertTime is 0
            let triggerTime: TimeInterval
            if active {
                triggerTime = absAlertTime - offset
            } else {
                triggerTime = 0
            }
            return AlertConfiguration(alertType: .slot2ShutdownImminent, active: active, trigger: .timeUntilAlert(triggerTime), beepRepeat: .every15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep, silent: silent)

        // slot3ExpirationReminder
        case .expirationReminder(let offset, let absAlertTime, let duration, let silent):
            let active = absAlertTime != 0 // disable if absAlertTime is 0
            let triggerTime: TimeInterval
            if active {
                triggerTime = absAlertTime - offset
            } else {
                triggerTime = 0
            }
            return AlertConfiguration(alertType: .slot3ExpirationReminder, active: active, duration: duration, trigger: .timeUntilAlert(triggerTime), beepRepeat: .every1MinuteFor3MinutesAndRepeatEvery15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep, silent: silent)

        // slot4LowReservoir
        case .lowReservoir(let units, let silent):
            let active = units != 0 // disable if units is 0
            return AlertConfiguration(alertType: .slot4LowReservoir, active: active, trigger: .unitsRemaining(units), beepRepeat: .every1MinuteFor3MinutesAndRepeatEvery60Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep, silent: silent)

        // slot5SuspendedReminder
        // A suspendTime of 0 is an untimed suspend
        // timePassed will be > 0 for an existing pod suspended reminder changing its silent state
        case .podSuspendedReminder(let active, _, let suspendTime, let timePassed, let silent):
            let reminderInterval, duration: TimeInterval
            var beepRepeat: BeepRepeat
            let beepType: BeepType
            let trigger: AlertTrigger
            var isActive: Bool = active

            if suspendTime == 0 || suspendTime >= TimeInterval(minutes: 30) {
                // Use 15-minute pod suspended reminder beeps for untimed or longer scheduled suspend times.
                reminderInterval = TimeInterval(minutes: 15)
                beepRepeat = .every15Minutes
            } else {
                // Use 5-minute pod suspended reminder beeps for shorter scheduled suspend times.
                reminderInterval = TimeInterval(minutes: 5)
                beepRepeat = .every5Minutes
            }

            // Make alert inactive if there isn't enough remaining in suspend time for a reminder beep.
            let suspendTimeRemaining = suspendTime - timePassed
            if suspendTime != 0 && suspendTimeRemaining <= reminderInterval {
                isActive = false
            }

            if isActive {
                // Compute the alert trigger time as the interval until the next upcoming reminder interval
                let triggerTime: TimeInterval = .seconds(reminderInterval - Double((Int(timePassed) % Int(reminderInterval))))

                if suspendTime == 0 {
                    duration = 0 // Untimed suspend, no duration
                } else {
                    // duration is from triggerTime to suspend time remaining
                    duration = suspendTimeRemaining - triggerTime
                }
                trigger = .timeUntilAlert(triggerTime) // time to next reminder interval with the suspend time
                beepType = .beep
            } else {
                beepRepeat = .once
                duration = 0
                trigger = .timeUntilAlert(.minutes(0))
                beepType = .noBeepCancel
            }
            return AlertConfiguration(alertType: .slot5SuspendedReminder, active: isActive, duration: duration, trigger: trigger, beepRepeat: beepRepeat, beepType: beepType, silent: silent)

        // slot6SuspendTimeExpired
        case .suspendTimeExpired(_, let suspendTime, let silent):
            let active = suspendTime != 0 // disable if suspendTime is 0
            let trigger: AlertTrigger
            let beepRepeat: BeepRepeat
            let beepType: BeepType
            if active {
                trigger = .timeUntilAlert(suspendTime)
                beepRepeat = suspendTimeExpiredBeepRepeat
                beepType = .bipBeepBipBeepBipBeepBipBeep
            } else {
                trigger = .timeUntilAlert(.minutes(0))
                beepRepeat = .once
                beepType = .noBeepCancel
            }
            return AlertConfiguration(alertType: .slot6SuspendTimeExpired, active: active, trigger: trigger, beepRepeat: beepRepeat, beepType: beepType, silent: silent)

        // slot7Expired
        case .waitingForPairingReminder:
            // After pod is powered up, beep every 10 minutes for up to 2 hours before pairing before failing
            let totalDuration: TimeInterval = .hours(2)
            let startOffset: TimeInterval = .minutes(10)
            return AlertConfiguration(alertType: .slot7Expired, duration: totalDuration - startOffset, trigger: .timeUntilAlert(startOffset), beepRepeat: .every5Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .finishSetupReminder:
            // After pod is paired, beep every 5 minutes for up to 1 hour for pod setup to complete before failing
            let totalDuration: TimeInterval = .hours(1)
            let startOffset: TimeInterval = .minutes(5)
            return AlertConfiguration(alertType: .slot7Expired, duration: totalDuration - startOffset, trigger: .timeUntilAlert(startOffset), beepRepeat: .every5Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .expired(let offset, let absAlertTime, let duration, let silent):
            // Normally used to alert at Pod.nominalPodLife (72 hours) for Pod.expirationAdvisoryWindow (7 hours)
            // 2 sets of beeps repeating every 60 minutes
            let active = absAlertTime != 0 // disable if absAlertTime is 0
            let triggerTime: TimeInterval
            if active {
                triggerTime = absAlertTime - offset
            } else {
                triggerTime = .minutes(0)
            }
            return AlertConfiguration(alertType: .slot7Expired, active: active, duration: duration, trigger: .timeUntilAlert(triggerTime), beepRepeat: .every60Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep, silent: silent)
        }
    }


    // MARK: - RawRepresentable
    public init?(rawValue: RawValue) {

        guard let name = rawValue["name"] as? String else {
            return nil
        }

        switch name {
        case "autoOff":
            guard let active = rawValue["active"] as? Bool,
                let countdownDuration = rawValue["countdownDuration"] as? TimeInterval else
            {
                return nil
            }
            let offset = rawValue["offset"] as? TimeInterval ?? 0
            let silent = rawValue["silent"] as? Bool ?? false
            self = .autoOff(active: active, offset: offset, countdownDuration: countdownDuration, silent: silent)
        case "shutdownImminent":
            guard let alarmTime = rawValue["alarmTime"] as? TimeInterval else {
                return nil
            }
            let offset = rawValue["offset"] as? TimeInterval ?? 0
            let offsetToUse, absAlertTime: TimeInterval
            if offset == 0 {
                // use default values as no offset value was found
                absAlertTime = defaultShutdownImminentTime
                offsetToUse = absAlertTime - alarmTime
            } else {
                absAlertTime = offset + alarmTime
                offsetToUse = offset
            }
            let silent = rawValue["silent"] as? Bool ?? false
            self = .shutdownImminent(offset: offsetToUse, absAlertTime: absAlertTime, silent: silent)
        case "expirationReminder":
            guard let alertTime = rawValue["alertTime"] as? TimeInterval else {
                return nil
            }
            let offset = rawValue["offset"] as? TimeInterval ?? 0
            let offsetToUse, absAlertTime: TimeInterval
            if offset == 0 {
                // use default values as no offset value was found
                absAlertTime = defaultExpirationReminderTime
                offsetToUse = absAlertTime - alertTime
            } else {
                absAlertTime = offset + alertTime
                offsetToUse = offset
            }
            let duration = rawValue["duration"] as? TimeInterval ?? 0
            let silent = rawValue["silent"] as? Bool ?? false
            self = .expirationReminder(offset: offsetToUse, absAlertTime: absAlertTime, duration: duration,  silent: silent)
        case "lowReservoir":
            guard let units = rawValue["units"] as? Double else {
                return nil
            }
            let silent = rawValue["silent"] as? Bool ?? false
            self = .lowReservoir(units: units, silent: silent)
        case "podSuspendedReminder":
            guard let active = rawValue["active"] as? Bool,
                let suspendTime = rawValue["suspendTime"] as? TimeInterval else
            {
                return nil
            }
            let offset = rawValue["offset"] as? TimeInterval ?? 0
            let silent = rawValue["silent"] as? Bool ?? false
            self = .podSuspendedReminder(active: active, offset: offset, suspendTime: suspendTime, silent: silent)
        case "suspendTimeExpired":
            guard let suspendTime = rawValue["suspendTime"] as? Double else {
                return nil
            }
            let offset = rawValue["offset"] as? TimeInterval ?? 0
            let silent = rawValue["silent"] as? Bool ?? false
            self = .suspendTimeExpired(offset: offset, suspendTime: suspendTime, silent: silent)
        case "waitingForPairingReminder":
            self = .waitingForPairingReminder
        case "finishSetupReminder":
            self = .finishSetupReminder
        case "expired":
            guard let alarmTime = rawValue["alarmTime"] as? TimeInterval,
                let duration = rawValue["duration"] as? TimeInterval else
            {
                return nil
            }
            let offset = rawValue["offset"] as? TimeInterval ?? 0
            let offsetToUse, absAlertTime: TimeInterval
            if offset == 0 {
                // use default values as no offset value was found
                absAlertTime = defaultExpiredTime
                offsetToUse = absAlertTime - alarmTime
            } else {
                absAlertTime = offset + alarmTime
                offsetToUse = offset
            }
            let silent = rawValue["silent"] as? Bool ?? false
            self = .expired(offset: offsetToUse, absAlertTime: absAlertTime, duration: duration, silent: silent)
        default:
            return nil
        }
    }

    public var rawValue: RawValue {

        let name: String = {
            switch self {
            case .autoOff:
                return "autoOff"
            case .notUsed:
                return "notUsed"
            case .shutdownImminent:
                return "shutdownImminent"
            case .expirationReminder:
                return "expirationReminder"
            case .lowReservoir:
                return "lowReservoir"
            case .podSuspendedReminder:
                return "podSuspendedReminder"
            case .suspendTimeExpired:
                return "suspendTimeExpired"
            case .waitingForPairingReminder:
                return "waitingForPairingReminder"
            case .finishSetupReminder:
                return "finishSetupReminder"
            case .expired:
                return "expired"
            }
        }()

        var rawValue: RawValue = [
            "name": name,
        ]

        switch self {
        case .autoOff(let active, let offset, let countdownDuration, let silent):
            rawValue["active"] = active
            rawValue["offset"] = offset
            rawValue["countdownDuration"] = countdownDuration
            rawValue["silent"] = silent
        case .shutdownImminent(let offset, let absAlertTime, let silent):
            rawValue["offset"] = offset
            rawValue["alarmTime"] = absAlertTime - offset
            rawValue["silent"] = silent
        case .expirationReminder(let offset, let absAlertTime, let duration, let silent):
            rawValue["offset"] = offset
            rawValue["alertTime"] = absAlertTime - offset
            rawValue["duration"] = duration
            rawValue["silent"] = silent
        case .lowReservoir(let units, let silent):
            rawValue["units"] = units
            rawValue["silent"] = silent
        case .podSuspendedReminder(let active, let offset, let suspendTime, _, let silent):
            rawValue["active"] = active
            rawValue["offset"] = offset
            rawValue["suspendTime"] = suspendTime
            rawValue["silent"] = silent
        case .suspendTimeExpired(let offset, let suspendTime, let silent):
            rawValue["offset"] = offset
            rawValue["suspendTime"] = suspendTime
            rawValue["silent"] = silent
        case .expired(let offset, let absAlertTime, let duration, let silent):
            rawValue["offset"] = offset
            rawValue["alarmTime"] = absAlertTime - offset
            rawValue["duration"] = duration
            rawValue["silent"] = silent
        default:
            break
        }

        return rawValue
    }
}

public enum AlertSlot: UInt8 {
    case slot0AutoOff = 0x00
    case slot1NotUsed = 0x01
    case slot2ShutdownImminent = 0x02
    case slot3ExpirationReminder = 0x03
    case slot4LowReservoir = 0x04
    case slot5SuspendedReminder = 0x05
    case slot6SuspendTimeExpired = 0x06
    case slot7Expired = 0x07

    public var bitMaskValue: UInt8 {
        return 1<<rawValue
    }

    public typealias AllCases = [AlertSlot]

    static var allCases: AllCases {
        return (0..<8).map { AlertSlot(rawValue: $0)! }
    }
}

public struct AlertSet: RawRepresentable, Collection, CustomStringConvertible, Equatable {

    public typealias RawValue = UInt8
    public typealias Index = Int

    public let startIndex: Int
    public let endIndex: Int

    private let elements: [AlertSlot]

    public static let none = AlertSet(rawValue: 0)

    public var rawValue: UInt8 {
        return elements.reduce(0) { $0 | $1.bitMaskValue }
    }

    public init(slots: [AlertSlot]) {
        self.elements = slots
        self.startIndex = 0
        self.endIndex = self.elements.count
    }

    public init(rawValue: UInt8) {
        self.init(slots: AlertSlot.allCases.filter { rawValue & $0.bitMaskValue != 0 })
    }

    public subscript(index: Index) -> AlertSlot {
        return elements[index]
    }

    public func index(after i: Int) -> Int {
        return i+1
    }

    public var description: String {
        if elements.count == 0 {
            return LocalizedString("No alerts", comment: "Pod alert state when no alerts are active")
        } else {
            let alarmDescriptions = elements.map { String(describing: $0) }
            return alarmDescriptions.joined(separator: ", ")
        }
    }

    public func compare(to other: AlertSet) -> (added: AlertSet, removed: AlertSet) {
        let added = Set(other.elements).subtracting(Set(elements))
        let removed = Set(elements).subtracting(Set(other.elements))
        return (added: AlertSet(slots: Array(added)), removed: AlertSet(slots: Array(removed)))
    }
}

// Returns true if there are any active suspend related alerts
public func hasActiveSuspendAlert(configuredAlerts: [AlertSlot : PodAlert]) -> Bool {
    if configuredAlerts.contains(where: { ($0.key == .slot5SuspendedReminder || $0.key == .slot6SuspendTimeExpired) && $0.value.configuration.active })
    {
        return true
    }
    return false
}

// Returns a descriptive string for all the alerts in alertSet
public func alertSetString(alertSet: AlertSet) -> String {

    if alertSet.isEmpty {
        // Don't bother displaying any additional info for an inactive alert
        return String(describing: alertSet)
    }

    let alertDescription = alertSet.map { (slot) -> String in
        switch slot {
        case .slot0AutoOff:
            return PodAlert.autoOff(active: true, offset: 0, countdownDuration: 0).description
        case .slot1NotUsed:
            return PodAlert.notUsed.description
        case .slot2ShutdownImminent:
            return PodAlert.shutdownImminent(offset: 0, absAlertTime: defaultShutdownImminentTime).description
        case .slot3ExpirationReminder:
            return PodAlert.expirationReminder(offset: 0, absAlertTime: defaultExpirationReminderTime).description
        case .slot4LowReservoir:
            return PodAlert.lowReservoir(units: Pod.maximumReservoirReading).description
        case .slot5SuspendedReminder:
            return PodAlert.podSuspendedReminder(active: true, offset: 0, suspendTime: .minutes(30)).description
        case .slot6SuspendTimeExpired:
            return PodAlert.suspendTimeExpired(offset: 0, suspendTime: .minutes(30)).description
        case .slot7Expired:
            return PodAlert.expired(offset: 0, absAlertTime: defaultExpiredTime, duration: Pod.expirationAdvisoryWindow).description
        }
    }

    return alertDescription.joined(separator: ", ")
}

func configuredAlertsString(configuredAlerts: [AlertSlot : PodAlert]) -> String {

    if configuredAlerts.isEmpty {
        return String(describing: configuredAlerts)
    }

    let configuredAlertString = configuredAlerts.map { (configuredAlert) -> String in

        let podAlert = configuredAlert.value
        let description = podAlert.description
        guard podAlert.configuration.active else {
            return description
        }

        switch podAlert {
        case .shutdownImminent(_, let absAlertTime, _):
            return String(format: "%@ @ %@", description, absAlertTime.timeIntervalStr)
        case .expirationReminder(_, let absAlertTime, _, _):
            return String(format: "%@ @ %@", description, absAlertTime.timeIntervalStr)
        case .lowReservoir(let unitTrigger, _):
            return String(format: "%@ @ %dU", description, Int(unitTrigger))
        case .podSuspendedReminder(_, let offset, let suspendTime, _, _):
            return String(format: "%@ ending @ %@ after %@", description, (offset + suspendTime).timeIntervalStr, suspendTime.timeIntervalStr)
        case .suspendTimeExpired(let offset, let suspendTime, _):
            return String(format: "%@ @ %@ after %@", description, (offset + suspendTime).timeIntervalStr, suspendTime.timeIntervalStr)
        case .expired(_, let absAlertTime, _, _):
            return String(format: "%@ @ %@", description, absAlertTime.timeIntervalStr)
        default:
            return ""
        }
    }

    return configuredAlertString.joined(separator: ", ")
}

// Returns an array of appropriate PodAlerts with the specified silent value
// for all the configuredAlerts given all the current pod conditions.
func regeneratePodAlerts(silent: Bool, configuredAlerts: [AlertSlot: PodAlert], activeAlertSlots: AlertSet, currentPodTime: TimeInterval, currentReservoirLevel: Double) -> [PodAlert] {
    var podAlerts: [PodAlert] = []

    for alert in configuredAlerts {
        // Just skip this alert if not previously active
        guard alert.value.configuration.active else {
            continue
        }

        // Map alerts to corresponding appropriate new ones at the current pod time using the specified silent value.
        switch alert.value {

        case .shutdownImminent(let offset, let alertTime, _):
            // alertTime is absolute when offset is non-zero, otherwise use  default value
            var absAlertTime = offset != 0 ? alertTime : defaultShutdownImminentTime
            if currentPodTime >= absAlertTime {
                // alert trigger is not in the future, make inactive using a 0 value
                absAlertTime = 0
            }
            // create new shutdownImminent podAlert using the current timeActive and the original absolute alert time
            podAlerts.append(PodAlert.shutdownImminent(offset: currentPodTime, absAlertTime: absAlertTime, silent: silent))

        case .expirationReminder(let offset, let alertTime, let alertDuration, _):
            let duration: TimeInterval

            // alertTime is absolute when offset is non-zero, otherwise use default value
            var absAlertTime = offset != 0 ? alertTime : defaultExpirationReminderTime
            if currentPodTime >= absAlertTime {
                // alert trigger is not in the future, make inactive using a 0 value
                absAlertTime = 0
                duration = 0
            } else {
                duration = alertDuration
            }
            // create new expirationReminder podAlert using the current active time and the original absolute alert time and duration
            podAlerts.append(PodAlert.expirationReminder(offset: currentPodTime, absAlertTime: absAlertTime, duration: duration, silent: silent))

        case .lowReservoir(let unitTrigger, _):
            let units: Double
            if currentReservoirLevel > unitTrigger {
                units = unitTrigger
            } else {
                // reservoir is no longer more than the unitTrigger, make inactive using a 0 value
                units = 0
            }
            podAlerts.append(PodAlert.lowReservoir(units: units, silent: silent))

        case .podSuspendedReminder(let active, let offset, let suspendTime, _, _):
            let timePassed: TimeInterval = min(currentPodTime - offset, .hours(2))
            // Pass along the computed time passed since alert was originally set so creation routine can
            // do all the grunt work dealing with varying reminder intervals and time passing scenarios.
            podAlerts.append(PodAlert.podSuspendedReminder(active: active, offset: offset, suspendTime: suspendTime, timePassed: timePassed, silent: silent))

        case .suspendTimeExpired(let lastOffset, let lastSuspendTime, _):
            let absAlertTime = lastOffset + lastSuspendTime
            let suspendTime: TimeInterval
            if currentPodTime >= absAlertTime {
                // alert trigger is no longer in the future
                if activeAlertSlots.contains(where: { $0 == .slot6SuspendTimeExpired } ) {
                    // The suspendTimeExpired alert has yet been acknowledged,
                    // set up a suspendTimeExpired alert for the next 15m interval.
                    // Compute a new suspendTime that is a multiple of 15 minutes
                    // from lastOffset which is at least one minute in the future.
                    let newOffsetSuspendTime = ceil((currentPodTime - lastOffset) / .minutes(15)) * .minutes(15)
                    let newAbsAlertTime = lastOffset + newOffsetSuspendTime
                    suspendTime = max(newAbsAlertTime - currentPodTime, .minutes(1))
                } else {
                    // The suspendTimeExpired alert was already been acknowledged,
                    // so now make this alert inactive by using a 0 suspendTime.
                    suspendTime = 0
                }
            } else {
                // recompute a new suspendTime based on the current pod time
                suspendTime = absAlertTime - currentPodTime
                print("setting new suspendTimeExpired suspendTime of \(suspendTime) with currentPodTime\(currentPodTime) and absAlertTime=\(absAlertTime)")
            }
            // create a new suspendTimeExpired PodAlert using the current active time and the computed suspendTime (if any)
            podAlerts.append(PodAlert.suspendTimeExpired(offset: currentPodTime, suspendTime: suspendTime, silent: silent))

        case .expired(let offset, let alertTime, let alertDuration, _):
            let duration: TimeInterval

            // alertTime is absolute when offset is non-zero, otherwise use default value
            var absAlertTime = offset != 0 ? alertTime : defaultExpiredTime
            if currentPodTime >= absAlertTime {
                // alert trigger is not in the future, make inactive using a 0 value
                absAlertTime = 0
                duration = 0
            } else {
                duration = alertDuration
            }
            // create new expired podAlert using the current active time and the original absolute alert time and duration
            podAlerts.append(PodAlert.expired(offset: currentPodTime, absAlertTime: absAlertTime, duration: duration, silent: silent))

        default:
            break
        }
    }
    return podAlerts
}
