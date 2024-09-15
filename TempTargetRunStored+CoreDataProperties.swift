import CoreData
import Foundation

public extension TempTargetRunStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempTargetRunStored> {
        NSFetchRequest<TempTargetRunStored>(entityName: "TempTargetRunStored")
    }

    @NSManaged var startDate: Date?
    @NSManaged var target: Decimal
    @NSManaged var id: UUID?
    @NSManaged var endDate: Date?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var tempTarget: TempTargetStored?
    @NSManaged var name: String?
}

extension TempTargetRunStored: Identifiable {}
