//
//  PodInfoActivationTime.swift
//  OmniKit
//
//  Created by Eelke Jager on 25/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Type 5 PodInfo returns the pod activation time and possible fault code & fault time
public struct PodInfoActivationTime : PodInfo {
    // OFF 1  2  3  4 5  6 7 8 9 10111213 1415161718
    // DATA   0  1  2 3  4 5 6 7 8 9 1011 1213141516
    // 02 11 05 PP QQQQ 00000000 00000000 MMDDYYHHMM

    public let podInfoType: PodInfoResponseSubType = .activationTime
    public let faultEventCode: FaultEventCode
    public let faultTime: TimeInterval
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let data: Data
    
    public init(encodedData: Data) throws {
        guard encodedData.count >= 16 else {
            throw MessageBlockError.notEnoughData
        }
        self.faultEventCode = FaultEventCode(rawValue: encodedData[1])
        self.faultTime = TimeInterval(minutes: Double((Int(encodedData[2]) << 8) + Int(encodedData[3])))
        self.year   = Int(encodedData[14])
        self.month  = Int(encodedData[12])
        self.day    = Int(encodedData[13])
        self.hour   = Int(encodedData[15])
        self.minute = Int(encodedData[16])
        self.data   = Data(encodedData)
    }
}

func activationTimeString(podInfoActivationTime: PodInfoActivationTime) -> String {
    var result: [String] = []

    // activation time info
    result.append(String(format: "Year:   %u", podInfoActivationTime.year))
    result.append(String(format: "Month:  %u", podInfoActivationTime.month))
    result.append(String(format: "Day:    %u", podInfoActivationTime.day))
    result.append(String(format: "Hour:   %u", podInfoActivationTime.hour))
    result.append(String(format: "Minute: %u", podInfoActivationTime.minute))

    // pod fault info
    result.append(String(format: "\nFault Time: %@", podInfoActivationTime.faultTime.timeIntervalStr))
    result.append(String(describing: podInfoActivationTime.faultEventCode))

    return result.joined(separator: "\n")
}
