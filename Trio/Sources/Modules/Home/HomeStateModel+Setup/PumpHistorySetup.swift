import CoreData
import Foundation

extension Home.StateModel {
    func setupInsulinArray() {
        Task {
            do {
                let ids = try await self.fetchInsulin()

                // Prefetch events and their bolus/tempBasal relationships into viewContext
                // with one IN-query so the subsequent per-ID materialization avoids N+1 faults.
                if !ids.isEmpty {
                    await viewContext.perform {
                        let prefetchRequest = NSFetchRequest<PumpEventStored>(entityName: "PumpEventStored")
                        prefetchRequest.predicate = NSPredicate(format: "SELF IN %@", ids)
                        prefetchRequest.relationshipKeyPathsForPrefetching = ["bolus", "tempBasal"]
                        prefetchRequest.returnsObjectsAsFaults = false
                        _ = try? self.viewContext.fetch(prefetchRequest)
                    }
                }

                let insulinObjects: [PumpEventStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateInsulinArray(with: insulinObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up insulin array: \(error)"
                )
            }
        }
    }

    private func fetchInsulin() async throws -> [NSManagedObjectID] {
        let pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        pumpHistoryFetchContext.name = "HomeStateModel.fetchInsulin"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: pumpHistoryFetchContext,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: true,
            batchSize: 30
        )

        return try await pumpHistoryFetchContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return pumpEvents.map(\.objectID)
        }
    }

    @MainActor private func updateInsulinArray(with insulinObjects: [PumpEventStored]) {
        insulinFromPersistence = insulinObjects

        manualTempBasal = apsManager.isManualTempBasal
        tempBasals = insulinFromPersistence.filter { $0.tempBasal != nil }

        suspendAndResumeEvents = insulinFromPersistence.filter {
            $0.type == EventType.pumpSuspend.rawValue || $0.type == EventType.pumpResume.rawValue
        }
    }

    // Setup Last Bolus to display the bolus progress bar
    // The predicate filters out all external boluses to prevent the progress bar from displaying the amount of an external bolus when an external bolus is added after a pump bolus
    func setupLastBolus() {
        Task {
            do {
                guard let id = try await self.fetchLastBolus() else { return }
                await updateLastBolus(with: id)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up last bolus: \(error)"
                )
            }
        }
    }

    func fetchLastBolus() async throws -> NSManagedObjectID? {
        let pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        pumpHistoryFetchContext.name = "HomeStateModel.fetchLastBolus"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: pumpHistoryFetchContext,
            predicate: NSPredicate.lastPumpBolus,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return try await pumpHistoryFetchContext.perform {
            guard let fetchedResults = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID).first
        }
    }

    @MainActor private func updateLastBolus(with ID: NSManagedObjectID) {
        do {
            lastPumpBolus = try viewContext.existingObject(with: ID) as? PumpEventStored
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the insulin array: \(error)"
            )
        }
    }
}
