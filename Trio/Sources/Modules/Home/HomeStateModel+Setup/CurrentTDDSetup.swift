import CoreData
import Foundation

extension Home.StateModel {
    func setupTDDArray() {
        Task {
            do {
                // Get the NSManagedObjectIDs
                let tddObjectIds = try await fetchTDDIDs()

                // Get the NSManagedObjects and map them to TDD on the Main Thread
                try await updateTDDArray(with: tddObjectIds, keyPath: \.fetchedTDDs)
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch TDDs: \(error)")
            }
        }
    }

    @MainActor private func updateTDDArray(
        with IDs: [NSManagedObjectID],
        keyPath: ReferenceWritableKeyPath<Home.StateModel, [TDD]>
    ) async throws {
        let tddObjects: [TDD] = try await CoreDataStack.shared
            .getNSManagedObject(with: IDs, context: viewContext)
            .compactMap { managedObject in
                // Safely extract date and total as optional
                let timestamp = managedObject.value(forKey: "date") as? Date
                let totalDailyDose = (managedObject.value(forKey: "total") as? NSNumber)?.decimalValue
                return TDD(totalDailyDose: totalDailyDose, timestamp: timestamp)
            }
        self[keyPath: keyPath] = tddObjects
    }

    private func fetchTDDIDs() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: tddFetchContext,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["total", "date", "objectID"]
        )

        return await tddFetchContext.perform {
            guard let fetchedResults = results as? [[String: Any]] else {
                return []
            }
            return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
        }
    }
}
