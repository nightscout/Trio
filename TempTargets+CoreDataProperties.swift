import Foundation
import CoreData


extension TempTargets {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TempTargets> {
        return NSFetchRequest<TempTargets>(entityName: "TempTargets")
    }

    @NSManaged public var active: Bool
    @NSManaged public var date: Date?
    @NSManaged public var duration: NSDecimalNumber?
    @NSManaged public var hbt: Double
    @NSManaged public var id: String?
    @NSManaged public var startDate: Date?

}

extension TempTargets : Identifiable {

}
