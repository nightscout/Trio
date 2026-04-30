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
        // Prefetch the determinations into viewContext with one IN-query so the
        // subsequent per-ID materialization avoids N+1 faults.
        if !IDs.isEmpty {
            let prefetchRequest = NSFetchRequest<OrefDetermination>(entityName: "OrefDetermination")
            prefetchRequest.predicate = NSPredicate(format: "SELF IN %@", IDs)
            prefetchRequest.returnsObjectsAsFaults = false
            _ = try? viewContext.fetch(prefetchRequest)
        }

        // Fetch the objects off the main thread
        let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
            .getNSManagedObject(with: IDs, context: viewContext)

        // Update the array on the main thread
        self[keyPath: keyPath] = determinationObjects
    }

    // Custom fetch to more efficiently filter only for cob and iob
    private func fetchCobAndIob() async throws -> [NSManagedObjectID] {
        let determinationFetchContext = CoreDataStack.shared.newTaskContext()
        determinationFetchContext.name = "HomeStateModel.fetchCobAndIob"

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
            self.yAxisChartDataCobChart(determinations: fetchedResults, on: determinationFetchContext)
            self.yAxisChartDataIobChart(determinations: fetchedResults, on: determinationFetchContext)
            return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
        }
    }
}
