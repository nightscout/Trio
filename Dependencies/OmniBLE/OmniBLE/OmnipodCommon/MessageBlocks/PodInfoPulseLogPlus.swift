//
//  PodInfoPulseLogPlus.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/PodInfoPulseLog.swift
//  Created by Eelke Jager on 22/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Type 3 Pod Info returns up to the last 60 pulse log entries pulse some additional info
public struct PodInfoPulseLogPlus : PodInfo {
    // CMD 1  2  3  4 5  6 7  8  9 10
    // DATA   0  1  2 3  4 5  6  7  8
    // 02 LL 03 PP QQQQ SSSS 04 3c XXXXXXXX ...

    public let podInfoType   : PodInfoResponseSubType = .pulseLogPlus
    public let faultEventCode: FaultEventCode // fault code
    public let timeFaultEvent: TimeInterval // fault time since activation
    public let timeActivation: TimeInterval // current time since activation
    public let entrySize     : Int // always 4
    public let maxEntries    : Int // always 60
    public let nEntries      : Int // how many 32-bit pulse log entries returned (calculated)
    public let pulseLog      : [UInt32]
    public let data          : Data

    public init(encodedData: Data) throws {
        guard encodedData[6] == MemoryLayout<UInt32>.size else {
            throw MessageError.unknownValue(value: encodedData[6], typeDescription: "pulseLog entry size")
        }
        let entrySize = Int(encodedData[6])
        let logStartByteOffset = 8 // starting byte offset of the pulse log in DATA
        let nLogBytesReturned = encodedData.count - logStartByteOffset
        let nEntries = nLogBytesReturned / entrySize
        let maxEntries = Int(encodedData[7])
        guard encodedData.count >= logStartByteOffset && (nLogBytesReturned & 0x3) == 0 else {
            throw MessageBlockError.notEnoughData // not enough data to start log or a non-integral # of pulse log entries
        }
        guard maxEntries >= nEntries else {
            throw MessageBlockError.parseError
        }
        self.entrySize = entrySize
        self.nEntries = nEntries
        self.maxEntries = maxEntries
        self.faultEventCode = FaultEventCode(rawValue: encodedData[1])
        self.timeFaultEvent = TimeInterval(minutes: Double((Int(encodedData[2]) << 8) + Int(encodedData[3])))
        self.timeActivation = TimeInterval(minutes: Double((Int(encodedData[4]) << 8) + Int(encodedData[5])))
        self.pulseLog = createPulseLog(encodedData: encodedData, logStartByteOffset: logStartByteOffset, nEntries: self.nEntries)
        self.data = encodedData
    }
}

func pulseLogPlusString(podInfoPulseLogPlus: PodInfoPulseLogPlus) -> String {
    var result: [String] = []

    result.append(String(format: "Pod Active: %@", podInfoPulseLogPlus.timeActivation.timeIntervalStr))
    result.append(String(format: "Fault Time: %@", podInfoPulseLogPlus.timeFaultEvent.timeIntervalStr))
    result.append(String(format: "%@\n", String(describing: podInfoPulseLogPlus.faultEventCode)))

    let lastPulseNumber = Int(podInfoPulseLogPlus.nEntries)
    result.append(pulseLogString(pulseLogEntries: podInfoPulseLogPlus.pulseLog, lastPulseNumber: lastPulseNumber))

    return result.joined(separator: "\n")
}
