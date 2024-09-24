import CoreData
import Foundation

extension Home.StateModel {
    // Setup Insulin
    func setupInsulinArray() {
        Task {
            let ids = await self.fetchInsulin()
            let insulinObjects: [PumpEventStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateInsulinArray(with: insulinObjects)
        }
    }

    private func fetchInsulin() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: pumpHistoryFetchContext,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: true
        )

        return await pumpHistoryFetchContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                return []
            }

            return pumpEvents.map(\.objectID)
        }
    }

    @MainActor private func updateInsulinArray(with insulinObjects: [PumpEventStored]) {
        insulinFromPersistence = insulinObjects

        // Filter tempbasals
        manualTempBasal = apsManager.isManualTempBasal
        tempBasals = insulinFromPersistence.filter({ $0.tempBasal != nil })

        // Suspension and resume events
        suspensions = insulinFromPersistence.filter {
            $0.type == EventType.pumpSuspend.rawValue || $0.type == EventType.pumpResume.rawValue
        }
        let lastSuspension = suspensions.last

        pumpSuspended = tempBasals.last?.timestamp ?? Date() > lastSuspension?.timestamp ?? .distantPast && lastSuspension?
            .type == EventType.pumpSuspend.rawValue
    }

    // Setup Last Bolus to display the bolus progress bar
    // The predicate filters out all external boluses to prevent the progress bar from displaying the amount of an external bolus when an external bolus is added after a pump bolus
    func setupLastBolus() {
        Task {
            guard let id = await self.fetchLastBolus() else { return }
            await updateLastBolus(with: id)
        }
    }

    func fetchLastBolus() async -> NSManagedObjectID? {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: pumpHistoryFetchContext,
            predicate: NSPredicate.lastPumpBolus,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return await pumpHistoryFetchContext.perform {
            guard let fetchedResults = results as? [PumpEventStored] else { return [].first }

            return fetchedResults.map(\.objectID).first
        }
    }

    @MainActor private func updateLastBolus(with ID: NSManagedObjectID) {
        do {
            lastPumpBolus = try viewContext.existingObject(with: ID) as? PumpEventStored
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the insulin array: \(error.localizedDescription)"
            )
        }
    }
}
