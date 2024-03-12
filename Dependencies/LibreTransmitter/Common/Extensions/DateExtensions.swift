//
//  DateExtensions.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 07/03/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

public extension Date {

    func rounded(on amount: Int, _ component: Calendar.Component) -> Date {
        let cal = Calendar.current
        let value = cal.component(component, from: self)

        // Compute nearest multiple of amount:
        let roundedValue = lrint(Double(value) / Double(amount)) * amount
        let newDate = cal.date(byAdding: component, value: roundedValue - value, to: self)!

        return newDate.floorAllComponents(before: component)
    }

    func floorAllComponents(before component: Calendar.Component) -> Date {
        // All components to round ordered by length
        let components = [Calendar.Component.year, .month, .day, .hour, .minute, .second, .nanosecond]

        guard let index = components.firstIndex(of: component) else {
            fatalError("Wrong component")
        }

        let cal = Calendar.current
        var date = self

        components.suffix(from: index + 1).forEach { roundComponent in
            let value = cal.component(roundComponent, from: date) * -1
            date = cal.date(byAdding: roundComponent, value: value, to: date)!
        }

        return date
    }

    static var LocaleWantsAMPM: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: NSLocale.current)!.contains("a")
    }

    func getFormattedDate(format: String) -> String {
        let dateformat = DateFormatter()
        dateformat.dateFormat = format
        return dateformat.string(from: self)
    }
    
    // Calculates the progress made from the start of the given range to the current date
    // Returns a percentage value between 0 and 100
    func getProgress(range: ClosedRange<Date>) -> Double {
        if self >= range.upperBound {
           return 100
        } else if self <= range.lowerBound {
           return 0
        }
        
        let totalTime = range.upperBound.timeIntervalSince(range.lowerBound)
        let elapsed = self.timeIntervalSince(range.lowerBound)
        // Calculate the progress made so far as a percentage of the total time
        return  (elapsed / totalTime) * 100
           
    }
}

extension DateComponents {
    func ToTimeString(wantsAMPM: Bool = Date.LocaleWantsAMPM) -> String {
        // print("hour: \(self.hour) minute: \(self.minute)")
        let date = Calendar.current.date(bySettingHour: self.hour ?? 0, minute: self.minute ?? 0, second: 0, of: Date())!

        let formatter = DateFormatter()
        formatter.dateStyle = DateFormatter.Style.long
        formatter.timeStyle = DateFormatter.Style.medium

        formatter.dateFormat = wantsAMPM ? "hh:mm a" : "HH:mm"
        return formatter.string(from: date)
    }
}

extension Array where Element == DateInterval {
    // Check for intersection among the intervals in the given array and return
    // the interval if found.
    func intersect() -> DateInterval? {
        // Algorithm:
        // We will compare first two intervals.
        // If an intersection is found, we will save the resultant interval
        // and compare it with the next interval in the array.
        // If no intersection is found at any iteration
        // it means the intervals in the array are disjoint. Break the loop and return nil
        // Otherwise return the last intersection.

        var previous = self.first
        for (index, element) in self.enumerated() {
            if index == 0 {
                continue
            }

            previous = previous?.intersection(with: element)

            if previous == nil {
                break
            }
        }

        return previous
    }
}
