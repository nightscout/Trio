import CoreData
import Foundation

extension InsulinStored {
    static func fetch(_ predicate: NSPredicate = .predicateForOneDayAgo) -> NSFetchRequest<InsulinStored> {
        let request = InsulinStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \InsulinStored.date, ascending: false)]
        request.fetchLimit = 100
        request.predicate = predicate
        return request
    }
}

extension NSPredicate {
    static var insulinForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "amount > 0 AND date >= %@", date as NSDate)
    }
}
