import CoreData
import Foundation

public extension CarbEntryStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CarbEntryStored> {
        NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored")
    }

    @NSManaged var carbs: Double
    @NSManaged var date: Date?
    @NSManaged var fat: Double
    @NSManaged var id: UUID?
    @NSManaged var isFPU: Bool
    @NSManaged var fpuID: UUID?
    @NSManaged var note: String?
    @NSManaged var protein: Double
    @NSManaged var isUploadedToNS: Bool
}

extension CarbEntryStored: Identifiable {}
