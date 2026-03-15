import CoreData
import Foundation

extension OpenAPS_Battery {
    static func fetch(_ predicate: NSPredicate = .predicateFor30MinAgo) -> NSFetchRequest<OpenAPS_Battery> {
        let request = OpenAPS_Battery.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OpenAPS_Battery.date, ascending: false)]
        request.fetchLimit = 1
        request.predicate = predicate
        return request
    }
}
