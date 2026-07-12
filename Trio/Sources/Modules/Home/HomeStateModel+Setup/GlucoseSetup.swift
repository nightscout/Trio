import CoreData
import Foundation

extension Home.StateModel {
    func setupGlucoseArray() {
        Task {
            do {
                let ids = try await self.fetchGlucose()
                let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                // The view context does not auto-merge other contexts' saves
                // (automaticallyMergesChangesFromParent = false), and getNSManagedObject returns cached
                // objects via existingObject(with:). So after FetchGlucoseManager writes
                // `smoothedGlucose` in its own context, the view context's cached GlucoseStored keeps a
                // stale (nil) smoothed value — which is why the smoothed line/popover only appeared
                // after an app relaunch reset the cache. Refresh each object so it re-faults from the
                // store and the smoothed values surface live.
                await viewContext.perform {
                    for object in glucoseObjects where !object.isFault {
                        self.viewContext.refresh(object, mergeChanges: false)
                    }
                }
                await updateGlucoseArray(with: glucoseObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up glucose array: \(error)"
                )
            }
        }
    }

    private func fetchGlucose() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: glucoseFetchContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: true,
            batchSize: 50
        )

        return try await glucoseFetchContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

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
