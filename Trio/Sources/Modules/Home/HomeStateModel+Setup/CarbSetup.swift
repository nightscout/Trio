import CoreData
import Foundation

extension Home.StateModel {
    func setupCarbsArray() {
        Task {
            do {
                let ids = try await self.fetchCarbs()
                let carbObjects: [CarbEntryStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateCarbsArray(with: carbObjects)
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error fetching carb objects: \(error) in \(#file):\(#line)")
            }
        }
    }

    private func fetchCarbs() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: carbsFetchContext,
            predicate: NSPredicate.carbsForChart,
            key: "date",
            ascending: false,
            batchSize: 5
        )

        return try await carbsFetchContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateCarbsArray(with objects: [CarbEntryStored]) {
        carbsFromPersistence = objects
    }

    func setupFPUsArray() {
        Task {
            do {
                let ids = try await self.fetchFPUs()
                let fpuObjects: [CarbEntryStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateFPUsArray(with: fpuObjects)
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error fetching FPU objects: \(error) in \(#file):\(#line)")
            }
        }
    }

    private func fetchFPUs() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: fpuFetchContext,
            predicate: NSPredicate.fpusForChart,
            key: "date",
            ascending: false
        )

        return try await fpuFetchContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateFPUsArray(with objects: [CarbEntryStored]) {
        fpusFromPersistence = objects
    }
}
