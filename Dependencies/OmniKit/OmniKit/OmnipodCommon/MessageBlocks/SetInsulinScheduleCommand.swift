//
//  SetInsulinScheduleCommand.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/24/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct SetInsulinScheduleCommand : NonceResyncableMessageBlock {
    
    fileprivate enum ScheduleTypeCode: UInt8 {
        case basalSchedule = 0
        case tempBasal = 1
        case bolus = 2
    }
    
    public enum DeliverySchedule {
        case basalSchedule(currentSegment: UInt8, secondsRemaining: UInt16, pulsesRemaining: UInt16, table: BasalDeliveryTable)
        case tempBasal(secondsRemaining: UInt16, firstSegmentPulses: UInt16, table: BasalDeliveryTable)
        case bolus(units: Double, timeBetweenPulses: TimeInterval, table: BolusDeliveryTable)
        
        fileprivate func typeCode() -> ScheduleTypeCode {
            switch self {
            case .basalSchedule:
                return .basalSchedule
            case .tempBasal:
                return .tempBasal
            case .bolus:
                return .bolus
            }
        }
        
        fileprivate var data: Data {
            switch self {
            case .basalSchedule(let currentSegment, let secondsRemaining, let pulsesRemaining, let table):
                var data = Data([currentSegment])
                data.appendBigEndian(secondsRemaining << 3)
                data.appendBigEndian(pulsesRemaining)
                for entry in table.entries {
                    data.append(entry.data)
                }
                return data

            case .tempBasal(let secondsRemaining, let firstSegmentPulses, let table):
                var data = Data([UInt8(table.numSegments())])
                data.appendBigEndian(secondsRemaining << 3)
                data.appendBigEndian(firstSegmentPulses)
                for entry in table.entries {
                    data.append(entry.data)
                }
                return data

            case .bolus(let units, let timeBetweenPulses, let table):
                let firstSegmentPulses = UInt16(round(units / Pod.pulseSize))
                let multiplier = UInt16(round(timeBetweenPulses * 8))
                let fieldA = firstSegmentPulses * multiplier

                var data = Data([UInt8(table.numSegments())])
                data.appendBigEndian(fieldA)
                data.appendBigEndian(firstSegmentPulses)
                for entry in table.entries {
                    data.append(entry.data)
                }
                return data

            }
        }
        
        fileprivate func checksum() -> UInt16 {
            switch self {
            case .basalSchedule( _, _, _, let table), .tempBasal(_, _, let table):
                return data[0..<5].reduce(0) { $0 + UInt16($1) } +
                    table.entries.reduce(0) { $0 + $1.checksum() }
            case .bolus(_, _, let table):
                return data[0..<5].reduce(0) { $0 + UInt16($1) } +
                    table.entries.reduce(0) { $0 + $1.checksum() }
            }
        }
    }
    
    public let blockType: MessageBlockType = .setInsulinSchedule
    
    public var nonce: UInt32
    public let deliverySchedule: DeliverySchedule
    
    public var data: Data {
        var data = Data([
            blockType.rawValue,
            UInt8(7 + deliverySchedule.data.count),
            ])
        data.appendBigEndian(nonce)
        data.append(deliverySchedule.typeCode().rawValue)
        data.appendBigEndian(deliverySchedule.checksum())
        data.append(deliverySchedule.data)
        return data
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 6 {
            throw MessageBlockError.notEnoughData
        }
        let length = encodedData[1]
        
        nonce = encodedData[2...].toBigEndian(UInt32.self)
        
        let checksum = encodedData[7...].toBigEndian(UInt16.self)

        guard let scheduleTypeCode = ScheduleTypeCode(rawValue: encodedData[6]) else {
            throw MessageError.unknownValue(value: encodedData[6], typeDescription: "ScheduleTypeCode")
        }

        switch scheduleTypeCode {
        case .basalSchedule:
            var entries = [InsulinTableEntry]()
            let numEntries = (length - 12) / 2
            for i in 0..<numEntries {
                let dataStart = Int(i*2 + 14)
                let entryData = encodedData.subdata(in: dataStart..<(dataStart+2))
                entries.append(InsulinTableEntry(encodedData: entryData))
            }
            let currentTableIndex = encodedData[9]
            let secondsRemaining = encodedData[10...].toBigEndian(UInt16.self) >> 3
            let pulsesRemaining = encodedData[12...].toBigEndian(UInt16.self)
            let table = BasalDeliveryTable(entries: entries)
            deliverySchedule = .basalSchedule(currentSegment: currentTableIndex, secondsRemaining: secondsRemaining, pulsesRemaining: pulsesRemaining, table: table)

        case .tempBasal:
            let secondsRemaining = encodedData[10...].toBigEndian(UInt16.self) >> 3
            let firstSegmentPulses = encodedData[12...].toBigEndian(UInt16.self)
            var entries = [InsulinTableEntry]()
            let numEntries = (length - 12) / 2
            for i in 0..<numEntries {
                let dataStart = Int(i*2 + 14)
                let entryData = encodedData.subdata(in: dataStart..<(dataStart+2))
                entries.append(InsulinTableEntry(encodedData: entryData))
            }
            let table = BasalDeliveryTable(entries: entries)
            deliverySchedule = .tempBasal(secondsRemaining: secondsRemaining, firstSegmentPulses: firstSegmentPulses, table: table)

        case .bolus:
            let fieldA = encodedData[10...].toBigEndian(UInt16.self)
            let unitRate = encodedData[12...].toBigEndian(UInt16.self)
            let units = Double(unitRate & 0x03ff) / Pod.pulsesPerUnit
            let timeBetweenPulses = unitRate > 0 ? Double(fieldA / unitRate) / 8 : 0

            var entries = [InsulinTableEntry]()
            let numEntries = (length - 12) / 2
            for i in 0..<numEntries {
                let dataStart = Int((i << 1) + 14)
                let entryData = encodedData.subdata(in: dataStart..<(dataStart+2))
                entries.append(InsulinTableEntry(encodedData: entryData))
            }
            let table = BolusDeliveryTable(entries: entries)
            deliverySchedule = .bolus(units: units, timeBetweenPulses: timeBetweenPulses, table: table)
        }
        
        guard checksum == deliverySchedule.checksum() else {
            throw MessageError.validationFailed(description: "InsulinDeliverySchedule checksum failed")
        }
    }
    
    public init(nonce: UInt32, deliverySchedule: DeliverySchedule) {
        self.nonce = nonce
        self.deliverySchedule = deliverySchedule
    }
    
    public init(nonce: UInt32, tempBasalRate: Double, duration: TimeInterval) {
        self.nonce = nonce
        let pulsesPerHour = Int(round(tempBasalRate / Pod.pulseSize))
        let table = BasalDeliveryTable(tempBasalRate: tempBasalRate, duration: duration)
        self.deliverySchedule = SetInsulinScheduleCommand.DeliverySchedule.tempBasal(secondsRemaining: 30*60, firstSegmentPulses: UInt16(pulsesPerHour / 2), table: table)
    }
    
    public init(nonce: UInt32, basalSchedule: BasalSchedule, scheduleOffset: TimeInterval) {
        let scheduleOffsetNearestSecond = round(scheduleOffset)
        let table = BasalDeliveryTable(schedule: basalSchedule)
        var rate = roundToSupportedBasalTimingRate(rate: basalSchedule.rateAt(offset: scheduleOffsetNearestSecond))
        if rate == 0.0 {
            // prevent app crash if a 0.0 scheduled basal ever gets here for Eros
            rate = nearZeroBasalRate
        }

        let segment = Int(scheduleOffsetNearestSecond / BasalDeliveryTable.segmentDuration)

        let segmentOffset = round(scheduleOffsetNearestSecond.truncatingRemainder(dividingBy: BasalDeliveryTable.segmentDuration))
        
        let timeRemainingInSegment = BasalDeliveryTable.segmentDuration - segmentOffset
        
        let timeBetweenPulses: TimeInterval = .hours(1) / (rate / Pod.pulseSize)
        
        let offsetToNextTenth = timeRemainingInSegment.truncatingRemainder(dividingBy: timeBetweenPulses / 10.0)
        
        let pulsesRemainingInSegment = (timeRemainingInSegment + timeBetweenPulses / 10.0 - offsetToNextTenth) / timeBetweenPulses
        
        self.deliverySchedule = SetInsulinScheduleCommand.DeliverySchedule.basalSchedule(currentSegment: UInt8(segment), secondsRemaining: UInt16(timeRemainingInSegment), pulsesRemaining: UInt16(pulsesRemainingInSegment), table: table)
        self.nonce = nonce
    }

    public init(nonce: UInt32, units: Double, timeBetweenPulses: TimeInterval = 0, extendedUnits: Double = 0, extendedDuration: TimeInterval = 0) {
        self.nonce = nonce
        let table = BolusDeliveryTable(units: units, extendedUnits: extendedUnits, extendedDuration: extendedDuration)
        let timeBetweenImmediatePulses = (units > 0.0 && timeBetweenPulses > 0) ? timeBetweenPulses : Pod.secondsPerBolusPulse
        self.deliverySchedule = SetInsulinScheduleCommand.DeliverySchedule.bolus(units: units, timeBetweenPulses: timeBetweenImmediatePulses, table: table)
    }
}

extension SetInsulinScheduleCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "SetInsulinScheduleCommand(nonce:\(Data(bigEndian: nonce).hexadecimalString), \(deliverySchedule))"
    }
}
