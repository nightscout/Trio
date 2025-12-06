import CoreData
import Foundation

public extension TempBasalStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempBasalStored> {
        NSFetchRequest<TempBasalStored>(entityName: "TempBasalStored")
    }

    @NSManaged var duration: Int16
    @NSManaged var rate: NSDecimalNumber?
    @NSManaged var tempType: String?
    @NSManaged var pumpEvent: PumpEventStored?
}

extension TempBasalStored: Identifiable {}
