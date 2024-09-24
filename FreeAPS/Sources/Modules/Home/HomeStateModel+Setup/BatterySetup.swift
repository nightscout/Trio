import CoreData
import Foundation

extension Home.StateModel {
    // Setup Battery
    func setupBatteryArray() {
        Task {
            let ids = await self.fetchBattery()
            let batteryObjects: [OpenAPS_Battery] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateBatteryArray(with: batteryObjects)
        }
    }

    private func fetchBattery() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OpenAPS_Battery.self,
            onContext: batteryFetchContext,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false
        )

        return await batteryFetchContext.perform {
            guard let fetchedResults = results as? [OpenAPS_Battery] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateBatteryArray(with objects: [OpenAPS_Battery]) {
        batteryFromPersistence = objects
    }
}
