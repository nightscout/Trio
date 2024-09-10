import CoreData
import Foundation

public extension TempTargets {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempTargets> {
        NSFetchRequest<TempTargets>(entityName: "TempTargets")
    }

    @NSManaged var active: Bool
    @NSManaged var date: Date?
    @NSManaged var duration: NSDecimalNumber?
    @NSManaged var hbt: Double
    @NSManaged var id: String?
    @NSManaged var startDate: Date?
}

extension TempTargets: Identifiable {}
