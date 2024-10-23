import CoreData
import Foundation

extension Home.StateModel {
    // Setup Overrides
    func setupOverrides() {
        Task {
            let ids = await self.fetchOverrides()
            let overrideObjects: [OverrideStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateOverrideArray(with: overrideObjects)
        }
    }

    private func fetchOverrides() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: overrideFetchContext,
            predicate: NSPredicate.lastActiveOverride, // this predicate filters for all Overrides within the last 24h
            key: "date",
            ascending: false
        )

        return await overrideFetchContext.perform {
            guard let fetchedResults = results as? [OverrideStored] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateOverrideArray(with objects: [OverrideStored]) {
        overrides = objects
    }

    @MainActor func calculateDuration(override: OverrideStored) -> TimeInterval {
        guard let overrideDuration = override.duration as? Double, overrideDuration != 0 else {
            return TimeInterval(60 * 60 * 24) // one day
        }
        return TimeInterval(overrideDuration * 60) // return seconds
    }

    @MainActor func calculateTarget(override: OverrideStored) -> Decimal {
        guard let overrideTarget = override.target, overrideTarget != 0 else {
            return 100 // default
        }
        return overrideTarget.decimalValue
    }

    // Setup expired Overrides
    func setupOverrideRunStored() {
        Task {
            let ids = await self.fetchOverrideRunStored()
            let overrideRunObjects: [OverrideRunStored] = await CoreDataStack.shared
                .getNSManagedObject(with: ids, context: viewContext)
            await updateOverrideRunStoredArray(with: overrideRunObjects)
        }
    }

    private func fetchOverrideRunStored() async -> [NSManagedObjectID] {
        let predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideRunStored.self,
            onContext: overrideFetchContext,
            predicate: predicate,
            key: "startDate",
            ascending: false
        )

        return await overrideFetchContext.perform {
            guard let fetchedResults = results as? [OverrideRunStored] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateOverrideRunStoredArray(with objects: [OverrideRunStored]) {
        overrideRunStored = objects
    }

    @MainActor func saveToOverrideRunStored(withID id: NSManagedObjectID) async {
        await viewContext.perform {
            do {
                guard let object = try self.viewContext.existingObject(with: id) as? OverrideStored else { return }

                let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                newOverrideRunStored.id = UUID()
                newOverrideRunStored.name = object.name
                newOverrideRunStored.startDate = object.date ?? .distantPast
                newOverrideRunStored.endDate = Date()
                newOverrideRunStored.target = NSDecimalNumber(decimal: self.calculateTarget(override: object))
                newOverrideRunStored.override = object
                newOverrideRunStored.isUploadedToNS = false

            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to initialize a new Override Run Object")
            }
        }
    }
}
