import CoreData
import Foundation

extension Home.StateModel {
    func setupGlucoseArray() {
        Task {
            let ids = await self.fetchGlucose()
            let glucoseObjects: [GlucoseStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateGlucoseArray(with: glucoseObjects)
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: glucoseFetchContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: true
        )

        return await glucoseFetchContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else { return [] }

            // Update Main Chart Y Axis Values
            // Perform everything on "context" to be thread safe
            self.yAxisChartData(glucoseValues: fetchedResults)

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateGlucoseArray(with objects: [GlucoseStored]) {
        glucoseFromPersistence = objects
        latestTwoGlucoseValues = Array(objects.suffix(2))
    }
}
