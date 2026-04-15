import CoreData
import Foundation

public extension Forecast {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Forecast> {
        NSFetchRequest<Forecast>(entityName: "Forecast")
    }

    @NSManaged var date: Date?
    @NSManaged var id: UUID?
    @NSManaged var type: String?
    @NSManaged var forecastValues: Set<ForecastValue>?
    @NSManaged var orefDetermination: OrefDetermination?
}

// MARK: Generated accessors for forecastValues

public extension Forecast {
    @objc(addForecastValuesObject:)
    @NSManaged func addToForecastValues(_ value: ForecastValue)

    @objc(removeForecastValuesObject:)
    @NSManaged func removeFromForecastValues(_ value: ForecastValue)

    @objc(addForecastValues:)
    @NSManaged func addToForecastValues(_ values: NSSet)

    @objc(removeForecastValues:)
    @NSManaged func removeFromForecastValues(_ values: NSSet)
}

extension Forecast: Identifiable {}
