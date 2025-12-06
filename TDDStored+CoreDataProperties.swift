import CoreData
import Foundation

public extension TDDStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TDDStored> {
        NSFetchRequest<TDDStored>(entityName: "TDDStored")
    }

    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var total: NSDecimalNumber?
    @NSManaged var bolus: NSDecimalNumber?
    @NSManaged var tempBasal: NSDecimalNumber?
    @NSManaged var scheduledBasal: NSDecimalNumber?
    @NSManaged var weightedAverage: NSDecimalNumber?
}

extension TDDStored: Identifiable {}
