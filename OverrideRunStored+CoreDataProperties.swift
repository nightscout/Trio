import CoreData
import Foundation

public extension OverrideRunStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<OverrideRunStored> {
        NSFetchRequest<OverrideRunStored>(entityName: "OverrideRunStored")
    }

    @NSManaged var endDate: Date?
    @NSManaged var startDate: Date?
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var id: UUID?
    @NSManaged var override: OverrideStored?
}

extension OverrideRunStored: Identifiable {}
