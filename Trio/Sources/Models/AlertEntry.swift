
import Foundation
import LoopKit
import UserNotifications

struct AlertEntry: JSON, Codable, Hashable {
    let alertIdentifier: String
    var acknowledgedDate: Date?
    var primitiveInterruptionLevel: Decimal?
    let issuedDate: Date
    let managerIdentifier: String
    let triggerType: Int16
    var triggerInterval: Decimal?
    let contentTitle: String?
    let contentBody: String?
    var errorMessage: String?

    static let local = "Trio"

    static func == (lhs: AlertEntry, rhs: AlertEntry) -> Bool {
        lhs.issuedDate == rhs.issuedDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(issuedDate)
    }

    private enum CodingKeys: String, CodingKey {
        case alertIdentifier
        case acknowledgedDate
        case primitiveInterruptionLevel
        case issuedDate
        case managerIdentifier
        case triggerType
        case triggerInterval
        case contentTitle
        case contentBody
        case errorMessage
    }
}

//
//  StoredAlert.swift
//  Loop
//
//  Created by Rick Pasetto on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

extension Alert.Trigger {
    enum StorageError: Error {
        case invalidStoredInterval
        case invalidStoredType
    }

    var storedType: Int16 {
        switch self {
        case .immediate: return 0
        case .delayed: return 1
        case .repeating: return 2
        }
    }

    var storedInterval: NSNumber? {
        switch self {
        case .immediate: return nil
        case let .delayed(interval): return NSNumber(value: interval)
        case let .repeating(repeatInterval): return NSNumber(value: repeatInterval)
        }
    }

    init(storedType: Int16, storedInterval: NSNumber?, storageDate: Date? = nil, now: Date = Date()) throws {
        switch storedType {
        case 0: self = .immediate
        case 1:
            if let storedInterval = storedInterval {
                if let storageDate = storageDate, storageDate <= now {
                    let intervalLeft = storedInterval.doubleValue - now.timeIntervalSince(storageDate)
                    if intervalLeft <= 0 {
                        self = .immediate
                    } else {
                        self = .delayed(interval: intervalLeft)
                    }
                } else {
                    self = .delayed(interval: storedInterval.doubleValue)
                }
            } else {
                throw StorageError.invalidStoredInterval
            }
        case 2:
            // Strange case here: if it is a repeating trigger, we can't really play back exactly
            // at the right "remaining time" and then repeat at the original period.  So, I think
            // the best we can do is just use the original trigger
            if let storedInterval = storedInterval {
                self = .repeating(repeatInterval: storedInterval.doubleValue)
            } else {
                throw StorageError.invalidStoredInterval
            }
        default:
            throw StorageError.invalidStoredType
        }
    }
}

extension Alert.InterruptionLevel {
    var storedValue: NSNumber {
        // Since this is arbitrary anyway, might as well make it match iOS's values
        switch self {
        case .active:
            if #available(iOS 15.0, *) {
                return NSNumber(value: UNNotificationInterruptionLevel.active.rawValue)
            } else {
                // https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/active
                return 1
            }
        case .timeSensitive:
            if #available(iOS 15.0, *) {
                return NSNumber(value: UNNotificationInterruptionLevel.timeSensitive.rawValue)
            } else {
                // https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive
                return 2
            }
        case .critical:
            if #available(iOS 15.0, *) {
                return NSNumber(value: UNNotificationInterruptionLevel.critical.rawValue)
            } else {
                // https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/critical
                return 3
            }
        }
    }

    init?(storedValue: NSNumber) {
        switch storedValue {
        case Self.active.storedValue: self = .active
        case Self.timeSensitive.storedValue: self = .timeSensitive
        case Self.critical.storedValue: self = .critical
        default:
            return nil
        }
    }
}
