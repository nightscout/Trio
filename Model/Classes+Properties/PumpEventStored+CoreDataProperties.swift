import CoreData
import Foundation

public extension PumpEventStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PumpEventStored> {
        NSFetchRequest<PumpEventStored>(entityName: "PumpEventStored")
    }

    @NSManaged var actionDuration: NSDecimalNumber?
    @NSManaged var id: String?
    @NSManaged var insulinType: String?
    @NSManaged var isMutable: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var isUploadedToHealth: Bool
    @NSManaged var isUploadedToTidepool: Bool
    @NSManaged var note: String?
    @NSManaged var peakTime: NSDecimalNumber?
    @NSManaged var syncIdentifier: String?
    @NSManaged var timestamp: Date?
    @NSManaged var type: String?
    @NSManaged var bolus: BolusStored?
    @NSManaged var tempBasal: TempBasalStored?
}

extension PumpEventStored: Identifiable {}
