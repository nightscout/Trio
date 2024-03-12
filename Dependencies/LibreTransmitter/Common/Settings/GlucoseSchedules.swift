//
//  GlucoseSchedules.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 19/04/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
// import MiaomiaoClient
public enum GlucoseScheduleAlarmResult: Int, CaseIterable {
    case none = 0
    case low
    case high

    func isAlarming() -> Bool {
        rawValue != GlucoseScheduleAlarmResult.none.rawValue
    }
}

enum GlucoseSchedulesValidationStatus {
    case success
    case error(String)
}

class GlucoseScheduleList: Codable, CustomStringConvertible {
    var description: String {
        "(schedules: \(schedules) )"
    }

    public var schedules = [GlucoseSchedule]()

    public var enabledSchedules: [GlucoseSchedule] {
        schedules.compactMap({ $0.enabled == true ? $0 : nil })
    }

    // this is only used by the ui to count total number of schedules
    public static let minimumSchedulesCount = 2

    public var activeSchedules: [GlucoseSchedule] {
        enabledSchedules.compactMap {
            if let activeTime = $0.getScheduleActiveToFrom() {
                let now = Date()
                return activeTime.contains(now) ? $0 : nil
            }
            return nil
        }
    }

    private func validateGlucoseThresholds() -> GlucoseSchedulesValidationStatus? {
        // This is on purpose
        // we check all chedules for valid thresholds
        for schedule in self.schedules {
            if let low = schedule.lowAlarm, let high = schedule.highAlarm {
                if low == high {
                    return .error("One of your glucose schedules had the same value for low and high thresholds")
                }
                if low > high {
                    return .error("One of your glucose schedules had a low threshold set above your high threshold")
                }
                // just for completness sake, this would never be called
                if high < low {
                    return .error("One of your glucose schedules had a high threshold set below your low threshold")
                }
            }
        }
        return nil
    }

    public func validateGlucoseSchedules() -> GlucoseSchedulesValidationStatus {
        if let errors = validateGlucoseThresholds() {
            return errors
        }

        // if we have zero or 1 enabled schedules, overlapping would not be possible
        // (there is nothing to overlap on), so we skip interval check
        guard self.enabledSchedules.count > 1 else {
            return .success
        }

        var sameStartEnd = false
        let intervals: [DateInterval] = enabledSchedules.compactMap({
            var schedule = $0.getScheduleActiveToFrom()
            if let start = schedule?.start, let end = schedule?.end {
                if start == end {
                    sameStartEnd = true
                    return nil
                }
            }
            // This compensates for Datetimes being closed range in nature
            // example,
            // interval1start = 12:00, interval1end=14:00
            // interval2start = 14:00, interval2end=24:00
            // interval1end and interval2 would collide when .intersect()-ing,
            // so we change interval1end to 13:59:59
            // and interval2end to 23:59:59
            // This function is only used in the gui for validation, so this is acceptable
            //
            if let end = schedule?.end {
                if let newEnd = Calendar.current.date(byAdding: .second, value: -1, to: end) {
                    schedule?.end = newEnd
                }
            }
            return schedule
        })
        if sameStartEnd {
            return .error("One interval had the same start and end!")
        }
        if let intersects = intervals.intersect() {
            print("Glucose schedule collided, not valid! \(intersects)")
            return .error("Glucose schedules had overlapping time intervals")
        }
        return .success
    }
    // for convenience
    public static var snoozedUntil: Date? {
        UserDefaults.standard.snoozedUntil
    }

    public static func isSnoozed() -> Bool {
        let now = Date()

        if let snoozedUntil {
            return snoozedUntil >= now
        }
        return false
    }

    public func getActiveAlarms(_ currentGlucoseInMGDL: Double) -> GlucoseScheduleAlarmResult {
        for schedule in self.activeSchedules {
            if let lowAlarm = schedule.lowAlarm, currentGlucoseInMGDL <= lowAlarm {
                return .low
            }
            if let highAlarm = schedule.highAlarm, currentGlucoseInMGDL >= highAlarm {
                return .high
            }
        }
        return .none
    }
}

class GlucoseSchedule: Codable, CustomStringConvertible {
    var from: DateComponents?
    var to: DateComponents?
    var lowAlarm: Double?
    var highAlarm: Double?
    var enabled: Bool?

    // glucose schedules are stored as standalone datecomponents (i.e. offsets)
    // this takes the current start of day and adds those offsets,
    // and returns a Dateinterval with those offsets applied
    public func getScheduleActiveToFrom() -> DateInterval? {
        guard let fromComponents = from, let toComponents = to else {
            return nil
        }

        let now = Date()
        let previousMidnight = Calendar.current.startOfDay(for: now)
        let helper = Calendar.current.date(byAdding: .day, value: 1, to: previousMidnight)!
        let nextMidnight = Calendar.current.startOfDay(for: helper)

        let fromDate: Date? =  Calendar.current.date(byAdding: fromComponents, to: previousMidnight)
        var toDate: Date?
        if  toComponents.minute == 0 && toComponents.hour == 0 {
            toDate = nextMidnight
        } else {
            toDate = Calendar.current.date(byAdding: toComponents, to: previousMidnight)!
        }

        if let fromDate, let toDate, toDate >= fromDate {
            return DateInterval(start: fromDate, end: toDate)
        }
        return nil
    }
    // stores the alarm. It does not synhronize the value with the underlaying userdefaults
    // that is up to the caller of this class
    public func storeLowAlarm(forUnit unit: HKUnit, lowAlarm: Double) {
        if unit == HKUnit.millimolesPerLiter {
            self.lowAlarm = lowAlarm * 18
            return
        }

        self.lowAlarm = lowAlarm
    }

    public func retrieveLowAlarm(forUnit unit: HKUnit) -> Double? {
        if let lowAlarm = self.lowAlarm {
            if unit == HKUnit.millimolesPerLiter {
                return (lowAlarm / 18).roundTo(places: 1)
            } else {
                return lowAlarm
            }
        }

        return nil
    }

    // stores the alarm. It does not synhronize the value with the underlaying userdefaults
    // that is up to the caller of this class
    public func storeHighAlarm(forUnit unit: HKUnit, highAlarm: Double) {
        if unit == HKUnit.millimolesPerLiter {
            self.highAlarm = highAlarm * 18
            return
        }

        self.highAlarm = highAlarm
    }
    public func retrieveHighAlarm(forUnit unit: HKUnit) -> Double? {
        if let highAlarm = self.highAlarm {
            if unit == HKUnit.millimolesPerLiter {
                return (highAlarm / 18).roundTo(places: 1)
            }
            return highAlarm
        }

        return nil
    }

    var description: String {
        "(from: \(String(describing: from)), to: \(String(describing: to)), low: \(String(describing: lowAlarm)), high: \(String(describing: highAlarm)), enabled: \(String(describing: enabled)))"
    }
}
