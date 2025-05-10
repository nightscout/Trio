import CoreData
import Foundation

extension Home.StateModel {
    func setupDeterminationsArray() {
        Task {
            do {
                // Get the NSManagedObjectIDs
                async let enactedObjectIds = determinationStorage
                    .fetchLastDeterminationObjectID(predicate: NSPredicate.enactedDetermination)
                async let enactedAndNonEnactedObjectIds = fetchCobAndIob()

                let enactedIDs = try await enactedObjectIds
                let enactedAndNonEnactedIds = try await enactedAndNonEnactedObjectIds

                // Get the NSManagedObjects and return them on the Main Thread
                try await updateDeterminationsArray(with: enactedIDs, keyPath: \.determinationsFromPersistence)
                try await updateDeterminationsArray(with: enactedAndNonEnactedIds, keyPath: \.enactedAndNonEnactedDeterminations)

                await updateForecastData()
            } catch let error as CoreDataError {
                debug(.default, "Core Data error in setupDeterminationsArray: \(error)")
            } catch {
                debug(.default, "Unexpected error in setupDeterminationsArray: \(error)")
            }
        }
    }

    @MainActor private func updateDeterminationsArray(
        with IDs: [NSManagedObjectID],
        keyPath: ReferenceWritableKeyPath<Home.StateModel, [OrefDetermination]>
    ) async throws {
        // Fetch the objects off the main thread
        let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
            .getNSManagedObject(with: IDs, context: viewContext)

        // Update the array on the main thread
        self[keyPath: keyPath] = determinationObjects
    }

    // Custom fetch to more efficiently filter only for cob and iob
    private func fetchCobAndIob() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: determinationFetchContext,
            predicate: NSPredicate.determinationsForCobIobCharts,
            key: "deliverAt",
            ascending: false,
            batchSize: 50,
            propertiesToFetch: ["cob", "iob", "deliverAt", "objectID"]
        )

        return try await determinationFetchContext.perform {
            guard let fetchedResults = results as? [[String: Any]] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            // Update Chart Scales
            self.yAxisChartDataCobChart(determinations: fetchedResults)
            self.yAxisChartDataIobChart(determinations: fetchedResults)
            return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
        }
    }
}
