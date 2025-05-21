//
//  BasalSchedule.swift
//  OmniBLE
//
//  From OmniKit/Model/BasalSchedule.swift
//  Created by Pete Schwamb on 4/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct BasalScheduleEntry: RawRepresentable, Equatable {
    
    public typealias RawValue = [String: Any]

    let rate: Double
    let startTime: TimeInterval
    
    public init(rate: Double, startTime: TimeInterval) {
        var rrate = roundToSupportedBasalRate(rate: rate)
        if rrate == 0 && Pod.zeroBasalRate == 0 {
            // Got a zero scheduled basal rate for an Eros pod, use the min allowed
            rrate = Pod.pulseSize
        }
        self.rate = rrate
        self.startTime = startTime
    }

    // MARK: - RawRepresentable
    public init?(rawValue: RawValue) {
        
        guard
            let rate = rawValue["rate"] as? Double,
            let startTime = rawValue["startTime"] as? Double
            else {
                return nil
        }
        
        self.rate = rate
        self.startTime = startTime
    }
    
    public var rawValue: RawValue {
        let rawValue: RawValue = [
            "rate": rate,
            "startTime": startTime
        ]
        
        return rawValue
    }
}

// A basal schedule starts at midnight and should contain 24 hours worth of entries
public struct BasalSchedule: RawRepresentable, Equatable {
    
    public typealias RawValue = [String: Any]

    let entries: [BasalScheduleEntry]
    
    public func rateAt(offset: TimeInterval) -> Double {
        let (_, entry, _) = lookup(offset: offset)
        return entry.rate
    }

    // Only valid for fixed offset timezones
    public func currentRate(using calendar: Calendar, at date: Date = Date()) -> Double {
        let midnight = calendar.startOfDay(for: date)
        return rateAt(offset: date.timeIntervalSince(midnight))
    }

    // Returns index, entry, and time remaining
    func lookup(offset: TimeInterval) -> (Int, BasalScheduleEntry, TimeInterval) {
        guard offset >= 0 && offset < .hours(24) else {
            fatalError("Schedule offset out of bounds")
        }
        
        var last: TimeInterval = .hours(24)
        for (index, entry) in entries.reversed().enumerated() {
            if entry.startTime <= offset {
                return (entries.count - (index + 1), entry, last - entry.startTime)
            }
            last = entry.startTime
        }
        fatalError("Schedule incomplete")
    }
    
    public init(entries: [BasalScheduleEntry]) {
        self.entries = entries
    }
    
    public func durations() -> [(rate: Double, duration: TimeInterval, startTime: TimeInterval)] {
        var last: TimeInterval = .hours(24)
        let durations = entries.reversed().map { (entry) -> (rate: Double, duration: TimeInterval, startTime: TimeInterval) in
            let duration = (rate: entry.rate, duration: last - entry.startTime, startTime: entry.startTime)
            last = entry.startTime
            return duration
        }
        return durations.reversed()
    }
    
    // MARK: - RawRepresentable
    public init?(rawValue: RawValue) {
        
        guard
            let entries = rawValue["entries"] as? [BasalScheduleEntry.RawValue]
            else {
                return nil
        }
        
        self.entries = entries.compactMap { BasalScheduleEntry(rawValue: $0) }
    }
    
    public var rawValue: RawValue {
        let rawValue: RawValue = [
            "entries": entries.map { $0.rawValue }
        ]
        
        return rawValue
    }
}

public extension Sequence where Element == BasalScheduleEntry {
    func adjacentEqualRatesMerged() -> [BasalScheduleEntry] {
        var output = [BasalScheduleEntry]()
        let _ = self.reduce(nil) { (lastRate, entry) -> TimeInterval? in
            if entry.rate != lastRate {
                output.append(entry)
            }
            return entry.rate
        }
        return output
    }
}


