//
//  TimeZone.swift
//  RileyLink
//
//  Created by Nate Racklyeft on 10/2/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

extension TimeZone {
    static var currentFixed: TimeZone {
        return TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT())!
    }

    var fixed: TimeZone {
        return TimeZone(secondsFromGMT: secondsFromGMT())!
    }
    
    /// This only works for fixed utc offset timezones
    func scheduleOffset(forDate date: Date) -> TimeInterval {
        var calendar = Calendar.current
        calendar.timeZone = self
        let components = calendar.dateComponents([.day , .month, .year], from: date)
        guard let startOfSchedule = calendar.date(from: components) else {
            fatalError("invalid date")
        }
        return date.timeIntervalSince(startOfSchedule)
    }
}
