import CoreData
import Foundation

public extension Forecast {
    static func fetch(_ predicate: NSPredicate, sortedBy keyPath: String, ascending: Bool) -> NSFetchRequest<Forecast> {
        let request = NSFetchRequest<Forecast>(entityName: "Forecast")
        request.sortDescriptors = [NSSortDescriptor(key: keyPath, ascending: ascending)]
        request.predicate = predicate
        return request
    }

    var forecastValuesArray: [ForecastValue] {
        let set = forecastValues as? Set<ForecastValue> ?? []
        return set.sorted { $0.index < $1.index }
    }
}
