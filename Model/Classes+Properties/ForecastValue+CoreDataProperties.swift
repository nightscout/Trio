import CoreData
import Foundation

public extension ForecastValue {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ForecastValue> {
        NSFetchRequest<ForecastValue>(entityName: "ForecastValue")
    }

    @NSManaged var index: Int32
    @NSManaged var value: Int32
    @NSManaged var forecast: Forecast?
}

extension ForecastValue: Identifiable {}
