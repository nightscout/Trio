import CoreData
import Foundation

extension Home.StateModel {
    func setupTDDArray() {
        Task {
            // Get the NSManagedObjectIDs
            async let tddObjectIds = fetchTDD()
            let tddIds = await tddObjectIds

            // Get the NSManagedObjects and map them to TDD on the Main Thread
            await updateTDDArray(with: tddIds, keyPath: \.fetchedTDDs)
        }
    }

    @MainActor private func updateTDDArray(
        with IDs: [NSManagedObjectID],
        keyPath: ReferenceWritableKeyPath<Home.StateModel, [TDD]>
    ) async {
        let tddObjects: [TDD] = await CoreDataStack.shared
            .getNSManagedObject(with: IDs, context: viewContext)
            .compactMap { managedObject in
                // Safely extract date and total as optional
                let timestamp = managedObject.value(forKey: "date") as? Date
                let totalDailyDose = (managedObject.value(forKey: "total") as? NSNumber)?.decimalValue
                return TDD(totalDailyDose: totalDailyDose, timestamp: timestamp)
            }
        self[keyPath: keyPath] = tddObjects
    }

    // Custom fetch to more efficiently filter only for cob and iob
    private func fetchTDD() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: tddFetchContext,
            predicate: NSPredicate.predicateForFourHoursAgo,
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
