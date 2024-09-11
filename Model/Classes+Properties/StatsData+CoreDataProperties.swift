import CoreData
import Foundation

public extension StatsData {
    @nonobjc class func fetchRequest() -> NSFetchRequest<StatsData> {
        NSFetchRequest<StatsData>(entityName: "StatsData")
    }

    @NSManaged var lastrun: Date?
}

extension StatsData: Identifiable {}
