import CoreData
import Foundation

extension Date {
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    static var oneDayAgoInMinutes: Date {
        Calendar.current.date(byAdding: .minute, value: -1440, to: Date())!
    }

    static var oneDayAgo: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    }

    static var oneHourAgo: Date {
        Calendar.current.date(byAdding: .minute, value: -60, to: Date())!
    }

    static var halfHourAgo: Date {
        Calendar.current.date(byAdding: .minute, value: -30, to: Date())!
    }

    static var twentyMinutesAgo: Date {
        Calendar.current.date(byAdding: .minute, value: -20, to: Date())!
    }

    static var twoHoursAgo: Date {
        Calendar.current.date(byAdding: .hour, value: -2, to: Date())!
    }

    static var fourHoursAgo: Date {
        Calendar.current.date(byAdding: .hour, value: -4, to: Date())!
    }

    static var sixHoursAgo: Date {
        Calendar.current.date(byAdding: .hour, value: -6, to: Date())!
    }

    static var oneWeekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    }

    static var oneMonthAgo: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    }

    static var threeMonthsAgo: Date {
        Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    }
}

extension NSPredicate {
    static let all = NSPredicate(format: "TRUEPREDICATE")

    static let none = NSPredicate(format: "FALSEPREDICATE")

    static var predicateForOneDayAgoInMinutes: NSPredicate {
        let date = Date.oneDayAgoInMinutes
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var carbsHistory: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@ AND carbs > 0", date as NSDate)
    }

    static var predicateForOneHourAgo: NSPredicate {
        let date = Date.oneHourAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateFor30MinAgo: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateFor20MinAgo: NSPredicate {
        let date = Date.twentyMinutesAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateFor30MinAgoForDetermination: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(format: "deliverAt >= %@", date as NSDate)
    }

    static var predicateFor120MinAgo: NSPredicate {
        let date = Date.twoHoursAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForFourHoursAgo: NSPredicate {
        let date = Date.fourHoursAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForSixHoursAgo: NSPredicate {
        let date = Date.sixHoursAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForOneWeek: NSPredicate {
        let date = Date.oneWeekAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForOneMonth: NSPredicate {
        let date = Date.oneMonthAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForThreeMonths: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static func predicateForDateBetween(start: Date, end: Date) -> NSPredicate {
        NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)
    }

    static func predicateForDeliverAtBetween(start: Date, end: Date) -> NSPredicate {
        NSPredicate(format: "deliverAt >= %@ AND deliverAt <= %@", start as NSDate, end as NSDate)
    }

    static func predicateForTimestampBetween(start: Date, end: Date) -> NSPredicate {
        NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", start as NSDate, end as NSDate)
    }
}
