//
//  PodInfoPulseLog.swift
//  OmniKit
//
//  Created by Eelke Jager on 26/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Type $50 Pod Info returns (up to) the most recent 50 32-bit pulse log entries
public struct PodInfoPulseLogRecent : PodInfo {
    // CMD 1  2  3 4  5 6 7 8
    // DATA   0  1 2  3 4 5 6
    // 02 LL 50 IIII XXXXXXXX ...

    public let podInfoType   : PodInfoResponseSubType = .pulseLogRecent
    public let indexLastEntry: Int // the pulse # for last pulse log entry
    public let nEntries      : Int // how many 32-bit pulse entries returned (calculated)
    public let pulseLog      : [UInt32]
    public let data          : Data

    public init(encodedData: Data) throws {
        let logStartByteOffset = 3 // starting byte offset of the pulse log in DATA
        let nLogBytesReturned = encodedData.count - logStartByteOffset
        guard encodedData.count >= logStartByteOffset && (nLogBytesReturned & 0x3) == 0 else {
            throw MessageBlockError.notEnoughData // not enough data to start log or a non-integral # of pulse log entries
        }
        self.nEntries = nLogBytesReturned / MemoryLayout<UInt32>.size
        self.indexLastEntry = Int((UInt16(encodedData[1]) << 8) | UInt16(encodedData[2]))
        self.pulseLog = createPulseLog(encodedData: encodedData, logStartByteOffset: logStartByteOffset, nEntries: self.nEntries)
        self.data = encodedData
    }
}

// Type $51 Pod info returns (up to) the most previous 50 32-bit pulse log entries
public struct PodInfoPulseLogPrevious : PodInfo {
    // CMD 1  2  3 4  5 6 7 8
    // DATA   0  1 2  3 4 5 6
    // 02 LL 51 NNNN XXXXXXXX ...

    public let podInfoType : PodInfoResponseSubType = .pulseLogPrevious
    public let nEntries    : Int // how many 32-bit pulse log entries returned
    public let pulseLog    : [UInt32]
    public let data        : Data

    public init(encodedData: Data) throws {
        let logStartByteOffset = 3 // starting byte offset of the pulse log in DATA
        let nLogBytesReturned = encodedData.count - logStartByteOffset
        guard encodedData.count >= logStartByteOffset && (nLogBytesReturned & 0x3) == 0  else {
            throw MessageBlockError.notEnoughData // first 3 bytes missing or non-integral # of pulse log entries
        }
        let nEntriesCalculated = nLogBytesReturned / MemoryLayout<UInt32>.size
        self.nEntries = Int((UInt16(encodedData[1]) << 8) | UInt16(encodedData[2]))
        // verify we actually got all the reported entries
        if self.nEntries > nEntriesCalculated {
            throw MessageBlockError.notEnoughData // some pulse log entry count mismatch issue
        }
        self.pulseLog = createPulseLog(encodedData: encodedData, logStartByteOffset: logStartByteOffset, nEntries: self.nEntries)
        self.data = encodedData
    }
}

func createPulseLog(encodedData: Data, logStartByteOffset: Int, nEntries: Int) -> [UInt32] {
    var pulseLog: [UInt32] = Array(repeating: 0, count: nEntries)
    var index = 0
    while index < nEntries {
        pulseLog[index] = encodedData[(logStartByteOffset+(index*4))...].toBigEndian(UInt32.self)
        index += 1
    }
    return pulseLog
}

extension BinaryInteger {
    var binaryDescription: String {
        var binaryString = ""
        var internalNumber = self
        var counter = 0

        for _ in (1...self.bitWidth) {
            binaryString.insert(contentsOf: "\(internalNumber & 1)", at: binaryString.startIndex)
            internalNumber >>= 1
            counter += 1
            if counter % 8 == 0 {
                binaryString.insert(contentsOf: " ", at: binaryString.startIndex)
            }
        }
        return binaryString
    }
}

public func pulseLogString(pulseLogEntries: [UInt32], lastPulseNumber: Int) -> String {
    var result: [String] = ["Pulse eeeeee0a pppliiib cccccccc dfgggggg"]
    var index = pulseLogEntries.count - 1
    var pulseNumber = lastPulseNumber
    while index >= 0 {
        result.append(String(format: "%04d:%@", pulseNumber, UInt32(pulseLogEntries[index]).binaryDescription))
        index -= 1
        pulseNumber -= 1
    }
    return result.joined(separator: "\n")
}
