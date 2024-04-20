import CoreData
import Foundation

public extension HbA1c {
    @nonobjc class func fetchRequest() -> NSFetchRequest<HbA1c> {
        NSFetchRequest<HbA1c>(entityName: "HbA1c")
    }

    @NSManaged var date: Date?
    @NSManaged var hba1c: NSDecimalNumber?
    @NSManaged var hba1c_1: NSDecimalNumber?
    @NSManaged var hba1c_7: NSDecimalNumber?
    @NSManaged var hba1c_30: NSDecimalNumber?
}

extension HbA1c: Identifiable {}
