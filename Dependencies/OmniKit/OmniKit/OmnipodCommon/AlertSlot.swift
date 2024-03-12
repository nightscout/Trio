//
//  Alert.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/24/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public enum AlertTrigger {
    case unitsRemaining(Double)
    case timeUntilAlert(TimeInterval)
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
    let trigger: AlertTrigger
    let active: Bool
    let duration: TimeInterval
    let beepRepeat: BeepRepeat
    let beepType: BeepType
    let autoOffModifier: Bool

    static let length = 6

    public init(alertType: AlertSlot, active: Bool = true, autoOffModifier: Bool = false, duration: TimeInterval, trigger: AlertTrigger, beepRepeat: BeepRepeat, beepType: BeepType) {
        self.slot = alertType
        self.active = active
        self.autoOffModifier = autoOffModifier
        self.duration = duration
        self.trigger = trigger
        self.beepRepeat = beepRepeat
        self.beepType = beepType
    }
}

extension AlertConfiguration: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "AlertConfiguration(slot:\(slot), active:\(active), autoOffModifier:\(autoOffModifier), duration:\(duration), trigger:\(trigger), beepRepeat:\(beepRepeat), beepType:\(beepType))"
    }
}



public enum PodAlert: CustomStringConvertible, RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    // 2 hours long, time for user to start pairing process
    case waitingForPairingReminder

    // 1 hour long, time for user to finish priming, cannula insertion
    case finishSetupReminder

    // User configurable with PDM (1-24 hours before 72 hour expiration) "Change Pod Soon"
    case expirationReminder(TimeInterval)

    // 72 hour alarm
    case expired(alertTime: TimeInterval, duration: TimeInterval)

    // 79 hour alarm (1 hour before shutdown)
    case shutdownImminent(TimeInterval)

    // reservoir below configured value alert
    case lowReservoir(Double)

    // auto-off timer; requires user input every x minutes
    case autoOff(active: Bool, countdownDuration: TimeInterval)

    // pod suspended reminder, before suspendTime; short beep every 15 minutes if > 30 min, else every 5 minutes
    case podSuspendedReminder(active: Bool, suspendTime: TimeInterval)

    // pod suspend time expired alarm, after suspendTime; 2 sets of beeps every min for 3 minutes repeated every 15 minutes
    case suspendTimeExpired(suspendTime: TimeInterval)

    public var description: String {
        var alertName: String
        switch self {
        case .waitingForPairingReminder:
            return LocalizedString("Waiting for pairing reminder", comment: "Description waiting for pairing reminder")
        case .finishSetupReminder:
            return LocalizedString("Finish setup reminder", comment: "Description for finish setup reminder")
        case .expirationReminder:
            alertName = LocalizedString("Expiration alert", comment: "Description for expiration alert")
        case .expired:
            alertName = LocalizedString("Expiration advisory", comment: "Description for expiration advisory")
        case .shutdownImminent:
            alertName = LocalizedString("Shutdown imminent", comment: "Description for shutdown imminent")
        case .lowReservoir(let units):
            alertName = String(format: LocalizedString("Low reservoir advisory (%1$gU)", comment: "Format string for description for low reservoir advisory (1: reminder units)"), units)
        case .autoOff:
            alertName = LocalizedString("Auto-off", comment: "Description for auto-off")
        case .podSuspendedReminder:
            alertName = LocalizedString("Pod suspended reminder", comment: "Description for pod suspended reminder")
        case .suspendTimeExpired:
            alertName = LocalizedString("Suspend time expired", comment: "Description for suspend time expired")
        }
        if self.configuration.active == false {
            alertName += LocalizedString(" (inactive)", comment: "Description for an inactive alert modifier")
        }
        return alertName
    }

    public var configuration: AlertConfiguration {
        switch self {
        case .waitingForPairingReminder:
            return AlertConfiguration(alertType: .slot7, duration: .minutes(110), trigger: .timeUntilAlert(.minutes(10)), beepRepeat: .every5Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .finishSetupReminder:
            return AlertConfiguration(alertType: .slot7, duration: .minutes(55), trigger: .timeUntilAlert(.minutes(5)), beepRepeat: .every5Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .expirationReminder(let alertTime):
            let active = alertTime != 0 // disable if alertTime is 0
            return AlertConfiguration(alertType: .slot3, active: active, duration: 0, trigger: .timeUntilAlert(alertTime), beepRepeat: .every1MinuteFor3MinutesAndRepeatEvery15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .expired(let alarmTime, let duration):
            let active = alarmTime != 0 // disable if alarmTime is 0
            return AlertConfiguration(alertType: .slot7, active: active, duration: duration, trigger: .timeUntilAlert(alarmTime), beepRepeat: .every60Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .shutdownImminent(let alarmTime):
            let active = alarmTime != 0 // disable if alarmTime is 0
            return AlertConfiguration(alertType: .slot2, active: active, duration: 0, trigger: .timeUntilAlert(alarmTime), beepRepeat: .every15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .lowReservoir(let units):
            let active = units != 0 // disable if units is 0
            return AlertConfiguration(alertType: .slot4, active: active, duration: 0, trigger: .unitsRemaining(units), beepRepeat: .every1MinuteFor3MinutesAndRepeatEvery60Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .autoOff(let active, let countdownDuration):
            return AlertConfiguration(alertType: .slot0, active: active, autoOffModifier: true, duration: .minutes(15), trigger: .timeUntilAlert(countdownDuration), beepRepeat: .every1MinuteFor15Minutes, beepType: .bipBeepBipBeepBipBeepBipBeep)
        case .podSuspendedReminder(let active, let suspendTime):
            // A suspendTime of 0 is an untimed suspend
            let reminderInterval, duration: TimeInterval
            let trigger: AlertTrigger
            let beepRepeat: BeepRepeat
            let beepType: BeepType
            if active {
                if suspendTime >= TimeInterval(minutes :30) {
                    // Use 15-minute pod suspended reminder beeps for longer scheduled suspend times as per PDM.
                    reminderInterval = TimeInterval(minutes: 15)
                    beepRepeat = .every15Minutes
                } else {
                    // Use 5-minute pod suspended reminder beeps for shorter scheduled suspend times.
                    reminderInterval = TimeInterval(minutes: 5)
                    beepRepeat = .every5Minutes
                }
                if suspendTime == 0 {
                    duration = 0 // Untimed suspend, no duration
                } else if suspendTime > reminderInterval {
                    duration = suspendTime - reminderInterval // End after suspendTime total time
                } else {
                    duration = .minutes(1) // Degenerate case, end ASAP
                }
                trigger = .timeUntilAlert(reminderInterval) // Start after reminderInterval has passed
                beepType = .beep
            } else {
                duration = 0
                trigger = .timeUntilAlert(.minutes(0))
                beepRepeat = .once
                beepType = .noBeepCancel
            }
            return AlertConfiguration(alertType: .slot5, active: active, duration: duration, trigger: trigger, beepRepeat: beepRepeat, beepType: beepType)
        case .suspendTimeExpired(let suspendTime):
            let active = suspendTime != 0 // disable if suspendTime is 0
            let trigger: AlertTrigger
            let beepRepeat: BeepRepeat
            let beepType: BeepType
            if active {
                trigger = .timeUntilAlert(suspendTime)
                beepRepeat = .every1MinuteFor3MinutesAndRepeatEvery15Minutes
                beepType = .bipBeepBipBeepBipBeepBipBeep
            } else {
                trigger = .timeUntilAlert(.minutes(0))
                beepRepeat = .once
                beepType = .noBeepCancel
            }
            return AlertConfiguration(alertType: .slot6, active: active, duration: 0, trigger: trigger, beepRepeat: beepRepeat, beepType: beepType)
        }
    }


    // MARK: - RawRepresentable
    public init?(rawValue: RawValue) {

        guard let name = rawValue["name"] as? String else {
            return nil
        }

        switch name {
        case "waitingForPairingReminder":
            self = .waitingForPairingReminder
        case "finishSetupReminder":
            self = .finishSetupReminder
        case "expirationReminder":
            guard let alertTime = rawValue["alertTime"] as? Double else {
                return nil
            }
            self = .expirationReminder(TimeInterval(alertTime))
        case "expired":
            guard let alarmTime = rawValue["alarmTime"] as? Double,
                let duration = rawValue["duration"] as? Double else
            {
                return nil
            }
            self = .expired(alertTime: TimeInterval(alarmTime), duration: TimeInterval(duration))
        case "shutdownImminent":
            guard let alarmTime = rawValue["alarmTime"] as? Double else {
                return nil
            }
            self = .shutdownImminent(alarmTime)
        case "lowReservoir":
            guard let units = rawValue["units"] as? Double else {
                return nil
            }
            self = .lowReservoir(units)
        case "autoOff":
            guard let active = rawValue["active"] as? Bool,
                let countdownDuration = rawValue["countdownDuration"] as? Double else
            {
                return nil
            }
            self = .autoOff(active: active, countdownDuration: TimeInterval(countdownDuration))
        case "podSuspendedReminder":
            guard let active = rawValue["active"] as? Bool,
                let suspendTime = rawValue["suspendTime"] as? Double else
            {
                return nil
            }
            self = .podSuspendedReminder(active: active, suspendTime: suspendTime)
        case "suspendTimeExpired":
            guard let suspendTime = rawValue["suspendTime"] as? Double else {
                return nil
            }
            self = .suspendTimeExpired(suspendTime: suspendTime)
        default:
            return nil
        }
    }

    public var rawValue: RawValue {

        let name: String = {
            switch self {
            case .waitingForPairingReminder:
                return "waitingForPairingReminder"
            case .finishSetupReminder:
                return "finishSetupReminder"
            case .expirationReminder:
                return "expirationReminder"
            case .expired:
                return "expired"
            case .shutdownImminent:
                return "shutdownImminent"
            case .lowReservoir:
                return "lowReservoir"
            case .autoOff:
                return "autoOff"
            case .podSuspendedReminder:
                return "podSuspendedReminder"
            case .suspendTimeExpired:
                return "suspendTimeExpired"
            }
        }()


        var rawValue: RawValue = [
            "name": name,
        ]

        switch self {
        case .expirationReminder(let alertTime):
            rawValue["alertTime"] = alertTime
        case .expired(let alarmTime, let duration):
            rawValue["alarmTime"] = alarmTime
            rawValue["duration"] = duration
        case .shutdownImminent(let alarmTime):
            rawValue["alarmTime"] = alarmTime
        case .lowReservoir(let units):
            rawValue["units"] = units
        case .autoOff(let active, let countdownDuration):
            rawValue["active"] = active
            rawValue["countdownDuration"] = countdownDuration
        case .podSuspendedReminder(let active, let suspendTime):
            rawValue["active"] = active
            rawValue["suspendTime"] = suspendTime
        case .suspendTimeExpired(let suspendTime):
            rawValue["suspendTime"] = suspendTime
        default:
            break
        }

        return rawValue
    }
}

public enum AlertSlot: UInt8 {
    case slot0 = 0x00
    case slot1 = 0x01
    case slot2 = 0x02
    case slot3 = 0x03
    case slot4 = 0x04
    case slot5 = 0x05
    case slot6 = 0x06
    case slot7 = 0x07

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
    // slot5 is for podSuspendedReminder and slot6 is for suspendTimeExpired
    if configuredAlerts.contains(where: { ($0.key == .slot5 || $0.key == .slot6) && $0.value.configuration.active }) {
        return true
    }
    return false
}
