import CoreData
import Foundation

public extension TempTargetStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempTargetStored> {
        NSFetchRequest<TempTargetStored>(entityName: "TempTargetStored")
    }

    @NSManaged var date: Date?
    @NSManaged var duration: NSDecimalNumber?
    @NSManaged var enabled: Bool
    @NSManaged var halfBasalTarget: NSDecimalNumber?
    @NSManaged var id: UUID?
    @NSManaged var isPreset: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var orderPosition: Int16
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var tempTargetRun: TempTargetRunStored?
}

extension TempTargetStored: Identifiable {}
