import CoreData
import Foundation

extension NSPredicate {
    static var fpusForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "fat > 0 AND protein > 0 AND isFPU == true AND date >= %@", date as NSDate)
    }

    static var carbsForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "carbs > 0 AND isFPU == false AND date >= %@", date as NSDate)
    }
}

extension MealsStored {
    static func fetch(_ predicate: NSPredicate = .predicateForOneDayAgo) -> NSFetchRequest<MealsStored> {
        let request = MealsStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MealsStored.date, ascending: false)]
        request.fetchLimit = 100
        request.predicate = predicate
//        request.propertiesToFetch = ["date", "carbs"]
//        request.resultType = .dictionaryResultType
        return request
    }
}
