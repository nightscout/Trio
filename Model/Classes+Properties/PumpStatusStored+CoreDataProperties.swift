import CoreData
import Foundation

public extension PumpStatusStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PumpStatusStored> {
        NSFetchRequest<PumpStatusStored>(entityName: "PumpStatusStored")
    }

    @NSManaged var basalDeliveryState: String?
    @NSManaged var date: Date?
}

extension PumpStatusStored: Identifiable {}
