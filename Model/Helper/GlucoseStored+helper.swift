import CoreData
import Foundation

extension GlucoseStored {
    static func fetch(_ predicate: NSPredicate = .all, ascending: Bool, fetchLimit: Int? = nil) -> NSFetchRequest<GlucoseStored> {
        let request = GlucoseStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: ascending)]
        request.predicate = predicate
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        return request
    }

    static func glucoseIsFlat(_ glucose: [GlucoseStored]) -> Bool {
        guard glucose.count >= 3 else { return false }

        let lastThreeValues = glucose.suffix(3)
        let firstValue = lastThreeValues.last?.glucose

        return lastThreeValues.allSatisfy { $0.glucose == firstValue }
    }

//    static func asyncFetch(_ predicate: NSPredicate = NSPredicate(value: true), completion: @escaping (NSAsynchronousFetchResult<GlucoseStored>)->Void) -> NSAsynchronousFetchRequest<GlucoseStored> {
//           let request: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
//           request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: true)]
//           request.predicate = predicate
//
//           // Erstelle einen NSAsynchronousFetchRequest mit einem Completion Handler
//           let asyncFetchRequest = NSAsynchronousFetchRequest<GlucoseStored>(fetchRequest: request) { result in
//               completion(result)
//           }
//
//           return asyncFetchRequest
//       }
}

extension NSPredicate {
    static var glucose: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isManual == %@ AND date >= %@", false as NSNumber, date as NSDate)
    }

    static var manualGlucose: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isManual == %@ AND date >= %@", true as NSNumber, date as NSDate)
    }
}
