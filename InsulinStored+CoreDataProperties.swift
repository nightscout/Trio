import CoreData
import Foundation

public extension InsulinStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<InsulinStored> {
        NSFetchRequest<InsulinStored>(entityName: "InsulinStored")
    }

    @NSManaged var amount: NSDecimalNumber?
    @NSManaged var date: Date?
    @NSManaged var external: Bool
    @NSManaged var id: UUID?
    @NSManaged var isSMB: Bool
}

extension InsulinStored: Identifiable {}
