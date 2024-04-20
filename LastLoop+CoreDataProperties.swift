import CoreData
import Foundation

public extension LastLoop {
    @nonobjc class func fetchRequest() -> NSFetchRequest<LastLoop> {
        NSFetchRequest<LastLoop>(entityName: "LastLoop")
    }

    @NSManaged var cob: NSDecimalNumber?
    @NSManaged var iob: NSDecimalNumber?
    @NSManaged var timestamp: Date?
}

extension LastLoop: Identifiable {}
