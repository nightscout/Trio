import CoreData
import Foundation

extension Home.StateModel {
    func setupDeterminationsArray() {
        Task {
            // Get the NSManagedObjectIDs
            async let enactedObjectIds = determinationStorage
                .fetchLastDeterminationObjectID(predicate: NSPredicate.enactedDetermination)
            async let enactedAndNonEnactedObjectIds = fetchCobAndIob()

            let enactedIDs = await enactedObjectIds
            let enactedAndNonEnactedIds = await enactedAndNonEnactedObjectIds

            // Get the NSManagedObjects and return them on the Main Thread
            await updateDeterminationsArray(with: enactedIDs, keyPath: \.determinationsFromPersistence)
            await updateDeterminationsArray(with: enactedAndNonEnactedIds, keyPath: \.enactedAndNonEnactedDeterminations)

            await updateForecastData()
        }
    }

    @MainActor private func updateDeterminationsArray(
        with IDs: [NSManagedObjectID],
        keyPath: ReferenceWritableKeyPath<Home.StateModel, [OrefDetermination]>
    ) async {
        // Fetch the objects off the main thread
        let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
            .getNSManagedObject(with: IDs, context: viewContext)

        // Update the array on the main thread
        self[keyPath: keyPath] = determinationObjects
    }

    // Custom fetch to more efficiently filter only for cob and iob
    private func fetchCobAndIob() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: determinationFetchContext,
            predicate: NSPredicate.determinationsForCobIobCharts,
            key: "deliverAt",
            ascending: false,
            batchSize: 50,
            propertiesToFetch: ["cob", "iob", "deliverAt", "objectID"]
        )

        debug(.businessLogic, "IOB AND COB FOR CHART: \(results)")

        return await determinationFetchContext.perform {
            guard let fetchedResults = results as? [[String: Any]] else {
                return []
            }

            // Update Chart Scales
            self.yAxisChartDataCobChart(determinations: fetchedResults)
            self.yAxisChartDataIobChart(determinations: fetchedResults)
            return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
        }
    }
}
