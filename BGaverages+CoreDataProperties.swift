import CoreData
import Foundation

public extension BGaverages {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BGaverages> {
        NSFetchRequest<BGaverages>(entityName: "BGaverages")
    }

    @NSManaged var average: NSDecimalNumber?
    @NSManaged var average_1: NSDecimalNumber?
    @NSManaged var average_7: NSDecimalNumber?
    @NSManaged var average_30: NSDecimalNumber?
    @NSManaged var date: Date?
}

extension BGaverages: Identifiable {}
