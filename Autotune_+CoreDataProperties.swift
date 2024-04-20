import CoreData
import Foundation

public extension Autotune_ {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Autotune_> {
        NSFetchRequest<Autotune_>(entityName: "Autotune_")
    }

    @NSManaged var basalProfile: NSObject?
    @NSManaged var carbRatio: NSDecimalNumber?
    @NSManaged var createdAt: Date?
    @NSManaged var sensitivity: NSDecimalNumber?
}

extension Autotune_: Identifiable {}
