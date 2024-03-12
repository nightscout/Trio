//
//  PodInfoTriggeredAlerts.swift
//  OmniKit
//
//  Created by Eelke Jager on 16/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Type 1 Pod Info returns information about the currently unacknowledged triggered alert values
// All triggered alerts values are the pod time when triggered for all current Eros and Dash pods.
// For at least earlier Eros pods, low reservoir triggered alerts might be the # of pulses remaining.
public struct PodInfoTriggeredAlerts: PodInfo {
    // CMD 1  2  3 4  5 6  7 8  910 1112 1314 1516 1718 1920
    // DATA   0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
    // 02 13 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV

    public let podInfoType: PodInfoResponseSubType = .triggeredAlerts
    public let unknown_word: UInt16
    public var alertActivations: [TimeInterval] = Array(repeating: 0, count: 8)
    public let data: Data

    public init(encodedData: Data) throws {
        guard encodedData.count >= 11 else {
            throw MessageBlockError.notEnoughData
        }

        // initialize the eight VVVV triggered alert values starting at offset 3
        for i in 0..<8 {
            let j = 3 + (2 * i)
            self.alertActivations[i] = TimeInterval(minutes: Double(encodedData[j...].toBigEndian(UInt16.self)))
        }
        self.unknown_word = encodedData[1...].toBigEndian(UInt16.self)
        self.data = encodedData
    }
}

private func triggeredAlerts(podInfoTriggeredAlerts: PodInfoTriggeredAlerts, startOffset: Int, sepString: String, printAll: Bool) -> String {
    var result: [String] = []

    for index in podInfoTriggeredAlerts.alertActivations.indices {
        // extract the alert slot debug description for a more helpful display
        let description = AlertSlot(rawValue: UInt8(index)).debugDescription
        let start = description.index(description.startIndex, offsetBy: startOffset)
        let end = description.index(description.endIndex, offsetBy: -1)
        let range = start..<end

        let triggeredTimeStr: String
        if printAll || podInfoTriggeredAlerts.alertActivations[index] != 0 {
            triggeredTimeStr = podInfoTriggeredAlerts.alertActivations[index].timeIntervalStr
        } else {
            triggeredTimeStr = ""
        }
        result.append(String(format: "%@: %@", String(description[range]), triggeredTimeStr))
    }

    return result.joined(separator: sepString)
}

func triggeredAlertsString(podInfoTriggeredAlerts: PodInfoTriggeredAlerts) -> String {
    return triggeredAlerts(podInfoTriggeredAlerts: podInfoTriggeredAlerts, startOffset: 27, sepString: "\n", printAll: false)
}

extension PodInfoTriggeredAlerts: CustomDebugStringConvertible {
    public var debugDescription: String {
        return triggeredAlerts(podInfoTriggeredAlerts: self, startOffset: 33, sepString: ", ", printAll: true)
    }
}
