import CoreData
import Foundation

public extension TherapyProfileEntryStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TherapyProfileEntryStored> {
        NSFetchRequest<TherapyProfileEntryStored>(entityName: "TherapyProfileEntryStored")
    }

    @NSManaged var high: NSDecimalNumber?
    @NSManaged var kind: String?
    @NSManaged var seconds: Int32
    @NSManaged var value: NSDecimalNumber?
    @NSManaged var profile: TherapyProfileStored?
}

extension TherapyProfileEntryStored: Identifiable {}
