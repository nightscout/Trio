import CoreData
import Foundation

public extension Autosens_ {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Autosens_> {
        NSFetchRequest<Autosens_>(entityName: "Autosens_")
    }

    @NSManaged var newisf: NSDecimalNumber?
    @NSManaged var ratio: NSDecimalNumber?
    @NSManaged var timestamp: Date?
}

extension Autosens_: Identifiable {}
