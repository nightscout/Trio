import CoreData
import Foundation

public extension TempBasalStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempBasalStored> {
        NSFetchRequest<TempBasalStored>(entityName: "TempBasalStored")
    }

    @NSManaged var deliveredUnits: NSDecimalNumber?
    @NSManaged var duration: Int16
    @NSManaged var endDate: Date?
    @NSManaged var isScheduledBasal: Bool
    @NSManaged var rate: NSDecimalNumber?
    @NSManaged var startDate: Date?
    @NSManaged var tempType: String?
    @NSManaged var pumpEvent: PumpEventStored?
}

extension TempBasalStored: Identifiable {}
