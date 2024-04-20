import CoreData
import Foundation

public extension BGmedian {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BGmedian> {
        NSFetchRequest<BGmedian>(entityName: "BGmedian")
    }

    @NSManaged var date: Date?
    @NSManaged var median: NSDecimalNumber?
    @NSManaged var median_1: NSDecimalNumber?
    @NSManaged var median_7: NSDecimalNumber?
    @NSManaged var median_30: NSDecimalNumber?
}

extension BGmedian: Identifiable {}
