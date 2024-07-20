import Foundation
import CoreData


extension StatsData {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<StatsData> {
        return NSFetchRequest<StatsData>(entityName: "StatsData")
    }

    @NSManaged public var lastrun: Date?

}

extension StatsData : Identifiable {

}
