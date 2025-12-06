import CoreData
import Foundation

public extension GlucoseStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<GlucoseStored> {
        NSFetchRequest<GlucoseStored>(entityName: "GlucoseStored")
    }

    @NSManaged var date: Date?
    @NSManaged var direction: String?
    @NSManaged var glucose: Int16
    @NSManaged var id: UUID?
    @NSManaged var isManual: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var isUploadedToHealth: Bool
    @NSManaged var isUploadedToTidepool: Bool
}

extension GlucoseStored: Identifiable {}
