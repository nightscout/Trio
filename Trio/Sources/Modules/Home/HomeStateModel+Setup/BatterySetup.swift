import CoreData
import Foundation

extension Home.StateModel {
    func setupBatteryArray() {
        Task {
            do {
                let ids = try await self.fetchBattery()
                let batteryObjects: [OpenAPS_Battery] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateBatteryArray(with: batteryObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up battery array: \(error)"
                )
            }
        }
    }

    private func fetchBattery() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OpenAPS_Battery.self,
            onContext: batteryFetchContext,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false
        )

        return try await batteryFetchContext.perform {
            guard let fetchedResults = results as? [OpenAPS_Battery] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateBatteryArray(with objects: [OpenAPS_Battery]) {
        batteryFromPersistence = objects
    }
}
