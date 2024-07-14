import CoreData
import Foundation
import Swinject

protocol DeterminationStorage {
    func fetchLastDeterminationObjectID(predicate: NSPredicate, fetchLimit: Int) async -> [NSManagedObjectID]
    func getForecasts(for determinationID: NSManagedObjectID, in context: NSManagedObjectContext) -> [Forecast]
    func getForecastValues(for forecastID: NSManagedObjectID, in context: NSManagedObjectContext) -> [ForecastValue]
}

final class BaseDeterminationStorage: DeterminationStorage, Injectable {
    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func fetchLastDeterminationObjectID(predicate: NSPredicate, fetchLimit: Int) async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: predicate,
            key: "deliverAt",
            ascending: false,
            fetchLimit: fetchLimit,
            batchSize: 50
        )
        return await backgroundContext.perform {
            results.map(\.objectID)
        }
    }

    func getForecasts(for determinationID: NSManagedObjectID, in context: NSManagedObjectContext) -> [Forecast] {
        do {
            guard let determination = try context.existingObject(with: determinationID) as? OrefDetermination,
                  let forecastSet = determination.forecasts,
                  let forecasts = Array(forecastSet) as? [Forecast]
            else {
                return []
            }
            return forecasts
        } catch {
            debugPrint(
                "Failed \(DebuggingIdentifiers.failed) to fetch OrefDetermination with ID \(determinationID): \(error.localizedDescription)"
            )
            return []
        }
    }

    func getForecastValues(for forecastID: NSManagedObjectID, in context: NSManagedObjectContext) -> [ForecastValue] {
        do {
            guard let forecast = try context.existingObject(with: forecastID) as? Forecast,
                  let forecastValueSet = forecast.forecastValues,
                  let forecastValues = Array(forecastValueSet) as? [ForecastValue]
            else {
                return []
            }
            return forecastValues.sorted(by: { $0.index < $1.index })
        } catch {
            debugPrint(
                "Failed \(DebuggingIdentifiers.failed) to fetch Forecast with ID \(forecastID): \(error.localizedDescription)"
            )
            return []
        }
    }
}
