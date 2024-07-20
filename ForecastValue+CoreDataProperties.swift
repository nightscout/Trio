import Foundation
import CoreData


extension ForecastValue {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ForecastValue> {
        return NSFetchRequest<ForecastValue>(entityName: "ForecastValue")
    }

    @NSManaged public var index: Int32
    @NSManaged public var value: Int32
    @NSManaged public var forecast: Forecast?

}

extension ForecastValue : Identifiable {

}
