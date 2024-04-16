import CoreData
import Foundation

extension Date {
    static var oneDayAgo: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    }

    static var halfHourAgo: Date {
        Calendar.current.date(byAdding: .minute, value: -30, to: Date())!
    }
}

extension NSPredicate {
    static var predicateForOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateFor30MinAgo: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(format: "date > %@", date as NSDate)
    }
}
