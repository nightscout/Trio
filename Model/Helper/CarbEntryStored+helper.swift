import CoreData
import Foundation

extension NSPredicate {
    static var fpusForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isFPU == true AND date >= %@", date as NSDate)
    }

    static var carbsForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isFPU == false AND date >= %@ AND carbs > 0", date as NSDate)
    }

    static var carbsForStats: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "date >= %@ AND isFPU == %@", date as NSDate, false as NSNumber)
    }

    static var carbsNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToNS == %@ AND isFPU == %@ AND carbs > 0",
            date as NSDate,
            false as NSNumber,
            false as NSNumber
        )
    }

    static var carbsNotYetUploadedToHealth: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToHealth == %@",
            date as NSDate,
            false as NSNumber
        )
    }

    static var carbsNotYetUploadedToTidepool: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToTidepool == %@",
            date as NSDate,
            false as NSNumber
        )
    }

    static var fpusNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToNS == %@ AND isFPU == %@",
            date as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }
}

extension CarbEntryStored {
    static func fetch(
        _ predicate: NSPredicate = .predicateForOneDayAgo,
        fetchLimit: Int = 100,
        ascending: Bool = false
    ) -> NSFetchRequest<CarbEntryStored> {
        let request = CarbEntryStored.fetchRequest() as NSFetchRequest<CarbEntryStored>
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CarbEntryStored.date, ascending: ascending)]
        request.fetchLimit = fetchLimit
        request.predicate = predicate
        return request
    }
}
