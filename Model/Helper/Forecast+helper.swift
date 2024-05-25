import CoreData
import Foundation

public extension Forecast {
    static func fetch(_ predicate: NSPredicate, ascending: Bool) -> NSFetchRequest<Forecast> {
        let request = NSFetchRequest<Forecast>(entityName: "Forecast")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Forecast.date, ascending: ascending)]
        request.fetchLimit = 1
        request.predicate = predicate

        return request
    }

    var forecastValuesArray: [ForecastValue] {
        let set = forecastValues ?? []
        return set.sorted { $0.index < $1.index }
    }
}
