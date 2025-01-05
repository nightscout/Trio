import CoreData
import Foundation

public extension TempTargetStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempTargetStored> {
        NSFetchRequest<TempTargetStored>(entityName: "TempTargetStored")
    }

    @NSManaged var enabled: Bool
    @NSManaged var date: Date?
    @NSManaged var duration: NSDecimalNumber?
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var isPreset: Bool
    @NSManaged var halfBasalTarget: NSDecimalNumber?
    @NSManaged var tempTargetRun: TempTargetRunStored?
    @NSManaged var orderPosition: Int16
}

extension TempTargetStored: Identifiable {}
