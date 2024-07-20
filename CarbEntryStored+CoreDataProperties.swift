import Foundation
import CoreData


extension CarbEntryStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CarbEntryStored> {
        return NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored")
    }

    @NSManaged public var carbs: Double
    @NSManaged public var date: Date?
    @NSManaged public var fat: Double
    @NSManaged public var fpuID: UUID?
    @NSManaged public var id: UUID?
    @NSManaged public var isFPU: Bool
    @NSManaged public var isUploadedToNS: Bool
    @NSManaged public var note: String?
    @NSManaged public var protein: Double

}

extension CarbEntryStored : Identifiable {

}
