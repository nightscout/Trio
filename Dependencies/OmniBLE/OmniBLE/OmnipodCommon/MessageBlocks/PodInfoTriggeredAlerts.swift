//
//  PodInfoTriggeredAlerts.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/PodInfoTriggeredAlerts.swift
//  Created by Eelke Jager on 16/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Type 1 Pod Info returns information about the currently unacknowledged triggered alert values
public struct PodInfoTriggeredAlerts: PodInfo {
    // CMD 1  2  3 4  5 6  7 8  910 1112 1314 1516 1718 1920
    // DATA   0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
    // 02 13 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV

    public let podInfoType: PodInfoResponseSubType = .triggeredAlerts
    public let unknown_word: UInt16
    public let alertsActivations: [AlertActivation]
    public let data: Data

    public struct AlertActivation {
        let triggeredAlertValue: TriggeredAlertValue

        public init(triggeredAlertValue: TriggeredAlertValue) {
            self.triggeredAlertValue = triggeredAlertValue
        }
    }

    public init(encodedData: Data) throws {
        guard encodedData.count >= 11 else {
            throw MessageBlockError.notEnoughData
        }

        let numAlerts = 8
        var activations = [AlertActivation]()
        var i = 3 // starting data index for first VVVV value
        for alertNum in (0..<numAlerts) {
            let val = Double(encodedData[i...].toBigEndian(UInt16.self))
            if AlertSlot(rawValue: UInt8(alertNum)) == .slot4LowReservoir {
                let triggeredAlertValue: TriggeredAlertValue = .unitsRemaining(val / Pod.pulsesPerUnit)
                activations.append(AlertActivation(triggeredAlertValue: triggeredAlertValue))
            } else {
                let triggeredAlertValue: TriggeredAlertValue = .podTime(TimeInterval(minutes: val))
                activations.append(AlertActivation(triggeredAlertValue: triggeredAlertValue))
            }
            i += 2
        }
        self.unknown_word = encodedData[1...].toBigEndian(UInt16.self)
        self.alertsActivations = activations
        self.data = encodedData
    }
}

public enum TriggeredAlertValue {
    case unitsRemaining(Double)
    case podTime(TimeInterval)
}

extension TriggeredAlertValue: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .unitsRemaining(let units):
            if units != 0 {
                return "\(Int(units))U"
            }
        case .podTime(let triggerTime):
            if triggerTime != 0 {
                return "\(triggerTime.timeIntervalStr)"
            }
        }
        return ""
    }
}

func triggeredAlertsString(podInfoTriggeredAlerts: PodInfoTriggeredAlerts) -> String {
    var result: [String] = []

    for index in podInfoTriggeredAlerts.alertsActivations.indices {
        // extract the alert slot debug description for a more helpful display
        let description = AlertSlot(rawValue: UInt8(index)).debugDescription
        let start = description.index(description.startIndex, offsetBy: 27)
        let end = description.index(description.endIndex, offsetBy: -1)
        let range = start..<end

        let alert = podInfoTriggeredAlerts.alertsActivations[index]
        result.append(String(format: "%@: %@", String(description[range]), String(describing: alert.triggeredAlertValue)))
    }

    return result.joined(separator: "\n")
}
