import CoreData
import Foundation

extension Home.StateModel {
    // Setup Overrides
    func setupOverrides() {
        Task {
            do {
                let ids = try await self.fetchOverrides()
                let overrideObjects: [OverrideStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateOverrideArray(with: overrideObjects)
            } catch let error as CoreDataError {
                debug(.default, "Core Data error in setupOverrides: \(error)")
            } catch {
                debug(.default, "Unexpected error in setupOverrides: \(error)")
            }
        }
    }

    private func fetchOverrides() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: overrideFetchContext,
            predicate: NSPredicate.lastActiveOverride, // this predicate filters for all Overrides within the last 24h
            key: "date",
            ascending: false
        )

        return try await overrideFetchContext.perform {
            guard let fetchedResults = results as? [OverrideStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
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

    // Setup expired Overrides
    func setupOverrideRunStored() {
        Task {
            do {
                let ids = try await self.fetchOverrideRunStored()
                let overrideRunObjects: [OverrideRunStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateOverrideRunStoredArray(with: overrideRunObjects)
            } catch let error as CoreDataError {
                debug(.default, "Core Data error in setupOverrideRunStored: \(error)")
            } catch {
                debug(.default, "Unexpected error in setupOverrideRunStored: \(error)")
            }
        }
    }

    private func fetchOverrideRunStored() async throws -> [NSManagedObjectID] {
        let predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideRunStored.self,
            onContext: overrideFetchContext,
            predicate: predicate,
            key: "startDate",
            ascending: false
        )

        return try await overrideFetchContext.perform {
            guard let fetchedResults = results as? [OverrideRunStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateOverrideRunStoredArray(with objects: [OverrideRunStored]) {
        overrideRunStored = objects
    }

    /// Cancels the running Override, creates an entry in the OverrideRunStored Core Data entity and posts a custom notification so that the AdjustmentsView gets updated
    @MainActor func cancelOverride(withID id: NSManagedObjectID) async {
        do {
            guard let profileToCancel = try viewContext.existingObject(with: id) as? OverrideStored else { return }

            profileToCancel.enabled = false

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            await saveToOverrideRunStored(object: profileToCancel)

            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        } catch let error as NSError {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Profile with error: \(error)")
        }
    }

    /// We can safely pass the NSManagedObject  as we are doing everything on the Main Actor
    @MainActor func saveToOverrideRunStored(object: OverrideStored) async {
        let newOverrideRunStored = OverrideRunStored(context: viewContext)
        newOverrideRunStored.id = UUID()
        newOverrideRunStored.name = object.name
        newOverrideRunStored.startDate = object.date ?? .distantPast
        newOverrideRunStored.endDate = Date()
        newOverrideRunStored.target = NSDecimalNumber(decimal: overrideStorage.calculateTarget(override: object))
        newOverrideRunStored.override = object
        newOverrideRunStored.isUploadedToNS = false

        do {
            guard viewContext.hasChanges else { return }
            try viewContext.save()
        } catch let error as NSError {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save an Override to the OverrideRunStored entity with error: \(error)"
            )
        }
    }
}
