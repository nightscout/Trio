import CoreData
import Foundation

public extension Target {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Target> {
        NSFetchRequest<Target>(entityName: "Target")
    }

    @NSManaged var current: NSDecimalNumber?
}

extension Target: Identifiable {}
