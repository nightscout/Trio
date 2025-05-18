import CoreData
import Foundation

public extension TempTargetRunStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempTargetRunStored> {
        NSFetchRequest<TempTargetRunStored>(entityName: "TempTargetRunStored")
    }

    @NSManaged var endDate: Date?
    @NSManaged var id: UUID?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var startDate: Date?
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var tempTarget: TempTargetStored?
}

extension TempTargetRunStored: Identifiable {}
