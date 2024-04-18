import CoreData
import Foundation

extension GlucoseStored {
    static func fetch(_ predicate: NSPredicate = .all) -> NSFetchRequest<GlucoseStored> {
        let request = GlucoseStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: true)]
        request.predicate = predicate
        return request
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
