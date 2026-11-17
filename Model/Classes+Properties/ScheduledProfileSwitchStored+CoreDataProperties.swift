import CoreData
import Foundation

public extension ScheduledProfileSwitchStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ScheduledProfileSwitchStored> {
        NSFetchRequest<ScheduledProfileSwitchStored>(entityName: "ScheduledProfileSwitchStored")
    }

    @NSManaged var id: String?
    @NSManaged var paused: Bool
    @NSManaged var profileName: String?
    @NSManaged var time: Int32
    @NSManaged var weekday: Int16
}

extension ScheduledProfileSwitchStored: Identifiable {}
