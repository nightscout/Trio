import CoreData
import Foundation

public extension TherapyProfileStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TherapyProfileStored> {
        NSFetchRequest<TherapyProfileStored>(entityName: "TherapyProfileStored")
    }

    @NSManaged var isActive: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var scheduledSwitchesSettledAt: Date?
    @NSManaged var entries: Set<TherapyProfileEntryStored>?
}

extension TherapyProfileStored: Identifiable {}
