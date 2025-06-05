//
//  PumpManagerAlert.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 7/9/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

public enum PumpManagerAlert: Hashable {
    case podExpireImminent(triggeringSlot: AlertSlot?)
    case userPodExpiration(triggeringSlot: AlertSlot?, scheduledExpirationReminderOffset: TimeInterval)
    case lowReservoir(triggeringSlot: AlertSlot?, lowReservoirReminderValue: Double)
    case suspendInProgress(triggeringSlot: AlertSlot?)
    case suspendEnded(triggeringSlot: AlertSlot?)
    case podExpiring(triggeringSlot: AlertSlot?)
    case finishSetupReminder(triggeringSlot: AlertSlot?)
    case unexpectedAlert(triggeringSlot: AlertSlot?)
    case timeOffsetChangeDetected

    var isRepeating: Bool {
        return repeatInterval != nil
    }

    var repeatInterval: TimeInterval? {
        switch self {
        case .suspendEnded:
            return .minutes(15)
        default:
            return nil
        }
    }

    var contentTitle: String {
        switch self {
        case .userPodExpiration:
            return LocalizedString("Pod Expiration Reminder", comment: "Alert content title for userPodExpiration pod alert")
        case .podExpiring:
            return LocalizedString("Pod Expired", comment: "Alert content title for podExpiring pod alert")
        case .podExpireImminent:
            return LocalizedString("Pod Expired", comment: "Alert content title for podExpireImminent pod alert")
        case .lowReservoir:
            return LocalizedString("Low Reservoir", comment: "Alert content title for lowReservoir pod alert")
        case .suspendInProgress:
            return LocalizedString("Suspend In Progress Reminder", comment: "Alert content title for suspendInProgress pod alert")
        case .suspendEnded:
            return LocalizedString("Resume Insulin", comment: "Alert content title for suspendEnded pod alert")
        case .finishSetupReminder:
            return LocalizedString("Pod Pairing Incomplete", comment: "Alert content title for finishSetupReminder pod alert")
        case .unexpectedAlert:
            return LocalizedString("Unexpected Alert", comment: "Alert content title for unexpected pod alert")
        case .timeOffsetChangeDetected:
            return LocalizedString("Time Change Detected", comment: "Alert content title for timeOffsetChangeDetected pod alert")
        }
    }

    var contentBody: String {
        switch self {
        case .userPodExpiration(_, let offset):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour]
            formatter.unitsStyle = .full
            let timeString = formatter.string(from: TimeInterval(offset))!
            return String(format: LocalizedString("Pod expires in %1$@.", comment: "Format string for alert content body for userPodExpiration pod alert. (1: time until expiration)"), timeString)
        case .podExpiring:
            return LocalizedString("Change Pod now. Pod has been active for 72 hours.", comment: "Alert content body for podExpiring pod alert")
        case .podExpireImminent:
            return LocalizedString("Change Pod now. Insulin delivery will stop in 1 hour.", comment: "Alert content body for podExpireImminent pod alert")
        case .lowReservoir(_, let lowReservoirReminderValue):
            let quantityFormatter = QuantityFormatter(for: .internationalUnit())
            let valueString = quantityFormatter.string(from: HKQuantity(unit: .internationalUnit(), doubleValue: lowReservoirReminderValue), for: .internationalUnit()) ?? String(describing: lowReservoirReminderValue)
            return String(format: LocalizedString("%1$@ insulin or less remaining in Pod. Change Pod soon.", comment: "Format string for alert content body for lowReservoir pod alert. (1: reminder value)"), valueString)
        case .suspendInProgress:
            return LocalizedString("Suspend In Progress Reminder", comment: "Alert content body for suspendInProgress pod alert")
        case .suspendEnded:
            return LocalizedString("The insulin suspension period has ended.\n\nYou can resume delivery from the banner on the home screen or from your pump settings screen. You will be reminded again in 15 minutes.", comment: "Alert content body for suspendEnded pod alert")
        case .finishSetupReminder:
            return LocalizedString("Please finish pairing your pod.", comment: "Alert content body for finishSetupReminder pod alert")
        case .unexpectedAlert(let triggeringSlot):
            let slotNumberString = triggeringSlot != nil ? String(describing: triggeringSlot!.rawValue) : "?"
            return String(format: LocalizedString("Unexpected Pod Alert #%1@!", comment: "Alert content body for unexpected pod alert (1: slotNumberString)"), slotNumberString)
        case .timeOffsetChangeDetected:
            return LocalizedString("The time on your pump is different from the current time. You can review the pump time and and sync to current time in settings.", comment: "Alert content body for timeOffsetChangeDetected pod alert")
        }
    }

    var triggeringSlot: AlertSlot? {
        switch self {
        case .userPodExpiration(let slot, _):
            return slot
        case .podExpiring(let slot):
            return slot
        case .podExpireImminent(let slot):
            return slot
        case .lowReservoir(let slot, _):
            return slot
        case .suspendInProgress(let slot):
            return slot
        case .suspendEnded(let slot):
            return slot
        case .finishSetupReminder(let slot):
            return slot
        case .unexpectedAlert(let slot):
            return slot
        case .timeOffsetChangeDetected:
            return nil
        }
    }

    // Override background (UserNotification) content

    var backgroundContentTitle: String {
        return contentTitle
    }

    var backgroundContentBody: String {
        switch self {
        case .suspendEnded:
            return LocalizedString("Suspension time is up. Open the app and resume.", comment: "Alert notification body for suspendEnded pod alert user notification")
        default:
            return contentBody
        }
    }


    var actionButtonLabel: String {
        return LocalizedString("Ok", comment: "Action button default text for PodAlerts")
    }

    var foregroundContent: Alert.Content {
        return Alert.Content(title: contentTitle, body: contentBody, acknowledgeActionButtonLabel: actionButtonLabel)
    }

    var backgroundContent: Alert.Content {
        return Alert.Content(title: backgroundContentTitle, body: backgroundContentBody, acknowledgeActionButtonLabel: actionButtonLabel)
    }

    var alertIdentifier: String {
        switch self {
        case .userPodExpiration:
            return "userPodExpiration"
        case .podExpiring:
            return "podExpiring"
        case .podExpireImminent:
            return "podExpireImminent"
        case .lowReservoir:
            return "lowReservoir"
        case .suspendInProgress:
            return "suspendInProgress"
        case .suspendEnded:
            return "suspendEnded"
        case .finishSetupReminder:
            return "finishSetupReminder"
        case .unexpectedAlert:
            return "unexpectedAlert"
        case .timeOffsetChangeDetected:
            return "timeOffsetChangeDetected"
        }
    }

    var repeatingAlertIdentifier: String {
        return alertIdentifier + "-repeating"
    }
}

extension PumpManagerAlert: RawRepresentable {

    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let identifier = rawValue["identifier"] as? String else {
            return nil
        }

        let slot: AlertSlot?

        if let rawSlot = rawValue["slot"] as? AlertSlot.RawValue {
            slot = AlertSlot(rawValue: rawSlot)
        } else {
            slot = nil
        }

        switch identifier {
        case "userPodExpiration":
            guard let offset = rawValue["offset"] as? TimeInterval, offset > 0 else {
                return nil
            }
            self = .userPodExpiration(triggeringSlot: slot, scheduledExpirationReminderOffset: offset)
        case "podExpiring":
            self = .podExpiring(triggeringSlot: slot)
        case "podExpireImminent":
            self = .podExpireImminent(triggeringSlot: slot)
        case "lowReservoir":
            guard let value = rawValue["value"] as? Double else {
                return nil
            }
            self = .lowReservoir(triggeringSlot: slot, lowReservoirReminderValue: value)
        case "suspendInProgress":
            self = .suspendInProgress(triggeringSlot: slot)
        case "suspendEnded":
            self = .suspendEnded(triggeringSlot: slot)
        case "unexpectedAlert":
            self = .unexpectedAlert(triggeringSlot: slot)
        case "timeOffsetChangeDetected":
            self = .timeOffsetChangeDetected
        default:
            return nil
        }
    }

    public var rawValue: [String : Any] {
        var rawValue: RawValue = [
            "identifier": alertIdentifier
        ]

        rawValue["slot"] = triggeringSlot?.rawValue

        switch self {
        case .lowReservoir(_, lowReservoirReminderValue: let value):
            rawValue["value"] = value
        case .userPodExpiration(_, scheduledExpirationReminderOffset: let offset):
            rawValue["offset"] = offset
        default:
            break
        }

        return rawValue
    }
}
