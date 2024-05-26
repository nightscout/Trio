import CoreData
import Foundation

@objc(PumpEventStored) public class PumpEventStored: NSManagedObject {
    let errorDomain = "PumpEventStoredErrorDomain"

    enum PumpEventErrorType: Int {
        case duplicate = 1001
    }

    override public func awakeFromInsert() {
        id_ = UUID().uuidString
    }

//    override public func validateForInsert() throws {
//        try super.validateForInsert()
//        try validateUniqueTimestamp()
//    }
//
//    private func validateUniqueTimestamp() throws {
//        guard let context = managedObjectContext, let timestamp = self.timestamp else {
//            return
//        }
//
//        let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
//        fetchRequest.predicate = NSPredicate.duplicateInLastFourLoops(timestamp)
//
//        do {
//            let results = try context.fetch(fetchRequest)
//            if !results.isEmpty {
//                print("Found duplicate PumpEventStored objects:")
//                for result in results {
//                    print("Timestamp: \(String(describing: result.timestamp))")
//                }
//                let error = NSError(domain: errorDomain, code: PumpEventErrorType.duplicate.rawValue, userInfo: [
//                    NSLocalizedDescriptionKey: "There is already a PumpEventStored with the same timestamp within the last 20 minutes.",
//                    "PumpEventErrorType": PumpEventErrorType.duplicate
//                ])
//                throw error
//            }
//        } catch {
//            throw error
//        }
//    }

//
//    override public func validateValue(_ value: AutoreleasingUnsafeMutablePointer<AnyObject?>, forKey key: String) throws {
//        try super.validateValue(value, forKey: key)
//
//        if key == "timestamp" {
//            try validateUniqueTimestamp(value)
//        }
//    }
//
//    private func validateUniqueTimestamp(_ value: AutoreleasingUnsafeMutablePointer<AnyObject?>) throws {
//        guard
//            let timestamp = value.pointee as? Date
//        else {
//            return
//        }
//
//        let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
//        fetchRequest.predicate = NSPredicate.duplicateInLastFourLoops(timestamp)
//
//        do {
//            let results = try CoreDataStack.shared.backgroundContext.fetch(fetchRequest)
//            if !results.isEmpty {
//                print("Found duplicate PumpEventStored objects:")
//                for result in results {
//                    print("Timestamp: \(String(describing: result.timestamp))")
//                }
//                let error = NSError(domain: errorDomain, code: PumpEventErrorType.duplicate.rawValue, userInfo: [
//                    NSLocalizedDescriptionKey: "There is already a PumpEventStored with the same timestamp within the last 4 loops.",
//                    "PumpEventErrorType": PumpEventErrorType.duplicate
//                ])
//                throw error
//            }
//        } catch {
//            throw error
//        }
//    }
}
