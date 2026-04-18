import CoreData
import Foundation

extension Home.StateModel {
    func setupCarbsArray() {
        Task {
            do {
                let ids = try await self.fetchCarbs()

                // Prefetch into viewContext with one IN-query so the subsequent
                // per-ID materialization avoids N+1 Z_PK selects.
                if !ids.isEmpty {
                    await viewContext.perform {
                        let prefetchRequest = NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored")
                        prefetchRequest.predicate = NSPredicate(format: "SELF IN %@", ids)
                        prefetchRequest.returnsObjectsAsFaults = false
                        _ = try? self.viewContext.fetch(prefetchRequest)
                    }
                }

                let carbObjects: [CarbEntryStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateCarbsArray(with: carbObjects)
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error fetching carb objects: \(error) in \(#file):\(#line)")
            }
        }
    }

    private func fetchCarbs() async throws -> [NSManagedObjectID] {
        let carbsFetchContext = CoreDataStack.shared.newTaskContext()
        carbsFetchContext.name = "HomeStateModel.fetchCarbs"

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

                // Prefetch into viewContext with one IN-query so the subsequent
                // per-ID materialization avoids N+1 Z_PK selects.
                if !ids.isEmpty {
                    await viewContext.perform {
                        let prefetchRequest = NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored")
                        prefetchRequest.predicate = NSPredicate(format: "SELF IN %@", ids)
                        prefetchRequest.returnsObjectsAsFaults = false
                        _ = try? self.viewContext.fetch(prefetchRequest)
                    }
                }

                let fpuObjects: [CarbEntryStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateFPUsArray(with: fpuObjects)
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error fetching FPU objects: \(error) in \(#file):\(#line)")
            }
        }
    }

    private func fetchFPUs() async throws -> [NSManagedObjectID] {
        let fpuFetchContext = CoreDataStack.shared.newTaskContext()
        fpuFetchContext.name = "HomeStateModel.fetchFPUs"

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
