import CoreData
import Foundation

public extension TherapyProfileSwitchStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TherapyProfileSwitchStored> {
        NSFetchRequest<TherapyProfileSwitchStored>(entityName: "TherapyProfileSwitchStored")
    }

    @NSManaged var date: Date?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var trigger: String?
}

extension TherapyProfileSwitchStored: Identifiable {}
