import CoreData
import Foundation

extension Home.StateModel {
    func setupCarbsArray() {
        Task {
            let ids = await self.fetchCarbs()
            let carbObjects: [CarbEntryStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateCarbsArray(with: carbObjects)
        }
    }

    private func fetchCarbs() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: carbsFetchContext,
            predicate: NSPredicate.carbsForChart,
            key: "date",
            ascending: false
        )

        return await carbsFetchContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateCarbsArray(with objects: [CarbEntryStored]) {
        carbsFromPersistence = objects
    }

    func setupFPUsArray() {
        Task {
            let ids = await self.fetchFPUs()
            let fpuObjects: [CarbEntryStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateFPUsArray(with: fpuObjects)
        }
    }

    private func fetchFPUs() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: fpuFetchContext,
            predicate: NSPredicate.fpusForChart,
            key: "date",
            ascending: false
        )

        return await fpuFetchContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateFPUsArray(with objects: [CarbEntryStored]) {
        fpusFromPersistence = objects
    }
}
