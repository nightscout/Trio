//
//  DetailedStatus.swift
//  OmniBLE
//
//  Based on OmniKit/MessageTransport/MessageBlocks/DetailedStatus.swift
//  Created by Pete Schwamb on 2/23/18.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

// DetailedStatus is the PodInfo subtype 2 returned for a type 2 GetStatus command and
// is also returned on a pod fault for any command normally returning a StatusResponse
public struct DetailedStatus : PodInfo, Equatable {
    // CMD 1  2  3  4  5 6  7  8 9 10 1112 1314 1516 17 18 19 20 21 2223
    // DATA   0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
    // 02 16 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW XX YYYY

    public let podInfoType: PodInfoResponseSubType = .detailedStatus
    public let podProgressStatus: PodProgressStatus
    public let deliveryStatus: DeliveryStatus
    public let bolusNotDelivered: Double
    public let lastProgrammingMessageSeqNum: UInt8 // updated by pod for 03, 08, $11, $19, $1A, $1C, $1E & $1F command messages
    public let totalInsulinDelivered: Double
    public let faultEventCode: FaultEventCode
    public let faultEventTimeSinceActivation: TimeInterval?
    public let reservoirLevel: Double
    public let timeActive: TimeInterval
    public let unacknowledgedAlerts: AlertSet
    public let faultAccessingTables: Bool
    public let errorEventInfo: ErrorEventInfo?
    public let receiverLowGain: UInt8
    public let radioRSSI: UInt8
    public let previousPodProgressStatus: PodProgressStatus?
    public let possibleFaultCallingAddress: UInt16?
    public let data: Data
    
    public init(encodedData: Data) throws {
        guard encodedData.count >= 22 else {
            throw MessageBlockError.notEnoughData
        }
        
        guard PodProgressStatus(rawValue: encodedData[1]) != nil else {
            throw MessageError.unknownValue(value: encodedData[1], typeDescription: "PodProgressStatus")
        }
        self.podProgressStatus = PodProgressStatus(rawValue: encodedData[1])!
        
        self.deliveryStatus = DeliveryStatus(rawValue: encodedData[2] & 0xf)!
        
        self.bolusNotDelivered = Double((Int(encodedData[3] & 0x3) << 8) | Int(encodedData[4])) / Pod.pulsesPerUnit
        
        self.lastProgrammingMessageSeqNum = encodedData[5]
        
        self.totalInsulinDelivered = Double(encodedData[6...7].toBigEndian(UInt16.self)) / Pod.pulsesPerUnit
        
        self.faultEventCode = FaultEventCode(rawValue: encodedData[8])
        
        let minutesSinceActivation = encodedData[9...10].toBigEndian(UInt16.self)
        if minutesSinceActivation != 0xffff {
            self.faultEventTimeSinceActivation = TimeInterval(minutes: Double(minutesSinceActivation))
        } else {
            self.faultEventTimeSinceActivation = nil
        }
        
        self.reservoirLevel = Double((Int(encodedData[11] & 0x3) << 8) + Int(encodedData[12])) / Pod.pulsesPerUnit
        
        self.timeActive = TimeInterval(minutes: Double(encodedData[13...14].toBigEndian(UInt16.self)))
        
        self.unacknowledgedAlerts =  AlertSet(rawValue: encodedData[15])
        
        self.faultAccessingTables = (encodedData[16] & 2) != 0
        
        if encodedData[17] == 0x00 {
            // no fault has occurred, errorEventInfo and previousPodProgressStatus not valid
            self.errorEventInfo = nil
            self.previousPodProgressStatus = nil
        } else {
            // fault has occurred, VV byte contains valid fault info
            let errorEventInfo = ErrorEventInfo(rawValue: encodedData[17])
            self.errorEventInfo = errorEventInfo
            // errorEventInfo.podProgressStatus is valid for both Eros and Dash on fault
            self.previousPodProgressStatus = errorEventInfo.podProgressStatus
        }
        
        // For Dash these values have always been zero
        self.receiverLowGain = UInt8(encodedData[18] >> 6)
        self.radioRSSI =  UInt8(encodedData[18] & 0x3F)
        
        // For Eros, encodedData[19] (XX) byte is the same previousPodProgressStatus nibble in the VV byte on fault.
        // For Dash, encodedData[19] (XX) byte is uninitialized or unknown, so use VV byte for previousPodProgressStatus.

        // Decode YYYY based on whether there was a pod fault
        if encodedData[8] == 0 {
            // For non-faults, YYYY contents not valid (either uninitialized data for Eros or some unknown content for Dash).
            self.possibleFaultCallingAddress = nil
        } else {
            // For Eros faults, YYYY is always uninitialized data from the previous command/response at the same buffer offset.
            // For Dash faults, YYYY could be a calling address of the fault routine for the first return after a pod fault,
            // subsequent returns will be byte swapped data from previous command/response at the same buffer offset.
            self.possibleFaultCallingAddress = encodedData[20...21].toBigEndian(UInt16.self) // only potentially valid for Dash
        }

        self.data = Data(encodedData)
    }

    public var isFaulted: Bool {
        return faultEventCode.faultType != .noFaults || podProgressStatus == .activationTimeExceeded
    }
}

extension DetailedStatus: CustomDebugStringConvertible {
    public typealias RawValue = Data
    public var debugDescription: String {
        var result = [
            "## DetailedStatus",
            "* rawHex: \(data.hexadecimalString)",
            "* podProgressStatus: \(podProgressStatus)",
            "* deliveryStatus: \(deliveryStatus.description)",
            "* bolusNotDelivered: \(bolusNotDelivered.twoDecimals) U",
            "* lastProgrammingMessageSeqNum: \(lastProgrammingMessageSeqNum)",
            "* totalInsulinDelivered: \(totalInsulinDelivered.twoDecimals) U",
            "* reservoirLevel: \(reservoirLevel == Pod.reservoirLevelAboveThresholdMagicNumber ? "50+" : reservoirLevel.twoDecimals) U",
            "* timeActive: \(timeActive.timeIntervalStr)",
            "* unacknowledgedAlerts: \(unacknowledgedAlerts)",
            "",
            ].joined(separator: "\n")
        if radioRSSI != 0 {
            result += [
                "* receiverLowGain: \(receiverLowGain)",
                "* radioRSSI: \(radioRSSI)",
                "",
                ].joined(separator: "\n")
        }
        if faultEventCode.faultType != .noFaults {
            result += [
                "* faultEventCode: \(faultEventCode.description)",
                "* faultAccessingTables: \(faultAccessingTables)",
                "* faultEventTimeSinceActivation: \(faultEventTimeSinceActivation?.timeIntervalStr ?? "NA")",
                "* errorEventInfo: \(errorEventInfo?.description ?? "NA")",
                "* previousPodProgressStatus: \(previousPodProgressStatus?.description ?? "NA")",
                "* possibleFaultCallingAddress: \(possibleFaultCallingAddress != nil ? String(format: "0x%04x", possibleFaultCallingAddress!) : "NA")",
                "",
                ].joined(separator: "\n")
        }
        return result
    }
}

extension DetailedStatus: RawRepresentable {
    public init?(rawValue: Data) {
        do {
            try self.init(encodedData: rawValue)
        } catch {
            return nil
        }
    }
    
    public var rawValue: Data {
        return data
    }
}

extension TimeInterval {
    var timeIntervalStr: String {
        var str: String = ""
        let hours = UInt(self / 3600)
        let minutes = UInt(self / 60) % 60
        let seconds = UInt(self) % 60
        if hours != 0 {
            str += String(format: "%uh", hours)
        }
        if minutes != 0 {
            str += String(format: "%um", minutes)
        }
        if seconds != 0 || str.isEmpty {
            str += String(format: "%us", seconds)
        }
        return str
    }
}

extension Double {
    var twoDecimals: String {
        return String(format: "%.2f", self)
    }
}

// Type for the ErrorEventInfo VV byte if valid
//    a: insulin state table corruption found during error logging
//   bb: internal 2-bit occlusion type
//    c: immediate bolus in progress during error
// dddd: Pod Progress at time of first logged fault event
//
public struct ErrorEventInfo: CustomStringConvertible, Equatable {
    public let rawValue: UInt8
    public let insulinStateTableCorruption: Bool // 'a' bit
    public let occlusionType: Int // 'bb' 2-bit occlusion type
    public let immediateBolusInProgress: Bool // 'c' bit
    public let podProgressStatus: PodProgressStatus // 'dddd' bits

    public var errorEventInfo: ErrorEventInfo? {
        return ErrorEventInfo(rawValue: rawValue)
    }

    public var description: String {
        let hexString = String(format: "%02X", rawValue)
        return [
            "rawValue: 0x\(hexString)",
            "insulinStateTableCorruption: \(insulinStateTableCorruption)",
            "occlusionType: \(occlusionType)",
            "immediateBolusInProgress: \(immediateBolusInProgress)",
            "podProgressStatus: \(podProgressStatus)",
            ].joined(separator: ", ")
    }

    init(rawValue: UInt8)  {
        self.rawValue = rawValue
        self.insulinStateTableCorruption = (rawValue & 0x80) != 0
        self.occlusionType = Int((rawValue & 0x60) >> 5)
        self.immediateBolusInProgress = (rawValue & 0x10) != 0
        self.podProgressStatus = PodProgressStatus(rawValue: rawValue & 0xF)!
    }
}
