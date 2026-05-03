import CoreData
import Foundation

extension History.StateModel {
    // MARK: - Entry Management

    /// Updates a carb/FPU entry with new values and handles the necessary cleanup and recreation of FPU entries
    /// - Parameters:
    ///   - treatmentObjectID: The ID of the entry to update
    ///   - newCarbs: The new carbs value
    ///   - newFat: The new fat value
    ///   - newProtein: The new protein value
    ///   - newNote: The new note text
    ///   - newDate: The new date for the entry
    func updateEntry(
        _ treatmentObjectID: NSManagedObjectID,
        newCarbs: Decimal,
        newFat: Decimal,
        newProtein: Decimal,
        newNote: String,
        newDate: Date
    ) {
        Task {
            do {
                // Get original date from entry to re-create the entry later with the updated values and the same date
                guard let originalEntry = await getOriginalEntryValues(treatmentObjectID) else { return }

                // Deletion logic for carb and FPU entries
                try await deleteOldEntries(
                    treatmentObjectID,
                    originalEntry: originalEntry,
                    newCarbs: newCarbs,
                    newFat: newFat,
                    newProtein: newProtein,
                    newNote: newNote
                )

                try await createNewEntries(
                    originalDate: newDate,
                    newCarbs: newCarbs,
                    newFat: newFat,
                    newProtein: newProtein,
                    newNote: newNote
                )

                await syncWithServices()

                // Perform a determine basal sync to update cob
                try await apsManager.determineBasalSync()

            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to update entry: \(error)")
            }
        }
    }

    private func createNewEntries(
        originalDate: Date,
        newCarbs: Decimal,
        newFat: Decimal,
        newProtein: Decimal,
        newNote: String
    ) async throws {
        let newEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: originalDate,
            carbs: newCarbs,
            fat: newFat,
            protein: newProtein,
            note: newNote,
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: newFat > 0 || newProtein > 0 ? UUID().uuidString : nil
        )

        // Handles internally whether to create fake carbs or not based on whether fat > 0 or protein > 0
        try await carbsStorage.storeCarbs([newEntry], areFetchedFromRemote: false)
    }

    /// Deletes the old carb/ FPU entries and creates new ones with updated values
    /// - Parameters:
    ///   - treatmentObjectID: The ID of the entry to delete
    ///   - originalDate: The original date to preserve
    ///   - newCarbs: The new carbs value
    ///   - newFat: The new fat value
    ///   - newProtein: The new protein value
    ///   - newNote: The new note text
    private func deleteOldEntries(
        _ treatmentObjectID: NSManagedObjectID,
        originalEntry: (
            entryValues: (date: Date, carbs: Double, fat: Double, protein: Double)?,
            entryId: NSManagedObjectID
        ),
        newCarbs _: Decimal,
        newFat _: Decimal,
        newProtein _: Decimal,
        newNote _: String
    ) async throws {
        if ((originalEntry.entryValues?.carbs ?? 0) == 0 && (originalEntry.entryValues?.fat ?? 0) > 0) ||
            ((originalEntry.entryValues?.carbs ?? 0) == 0 && (originalEntry.entryValues?.protein ?? 0) > 0)
        {
            // Delete the zero-carb-entry and all its carb equivalents connected by the same fpuID from remote services and Core Data
            // Use fpuID
            try await deleteCarbs(treatmentObjectID, isFpuOrComplexMeal: true)
        } else if ((originalEntry.entryValues?.carbs ?? 0) > 0 && (originalEntry.entryValues?.fat ?? 0) > 0) ||
            ((originalEntry.entryValues?.carbs ?? 0) > 0 && (originalEntry.entryValues?.protein ?? 0) > 0)
        {
            // Delete carb entry and carb equivalents that are all connected by the same fpuID from remote services and Core Data
            // Use fpuID
            try await deleteCarbs(treatmentObjectID, isFpuOrComplexMeal: true)

        } else {
            // Delete just the carb entry since there are no carb equivalents
            // Use NSManagedObjectID
            try await deleteCarbs(treatmentObjectID)
        }
    }

    /// Retrieves the original entry values
    /// - Parameter objectID: The ID of the entry
    /// - Returns: A tuple of the old entry values and its original date and the objectID or nil
    private func getOriginalEntryValues(_ objectID: NSManagedObjectID) async
        -> (entryValues: (date: Date, carbs: Double, fat: Double, protein: Double)?, entryId: NSManagedObjectID)?
    {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "updateContext"
        context.transactionAuthor = "updateEntry"

        return await context.perform {
            do {
                guard let entry = try context.existingObject(with: objectID) as? CarbEntryStored, let entryDate = entry.date
                else { return nil }

                return (
                    entryValues: (date: entryDate, carbs: entry.carbs, fat: entry.fat, protein: entry.protein),
                    entryId: entry.objectID
                )
            } catch let error as NSError {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to get original date with error: \(error.userInfo)")
                return nil
            }
        }
    }

    /// Synchronizes the FPU/ Carb entry with all remote services in parallel
    private func syncWithServices() async {
        async let nightscoutUpload: () = provider.nightscoutManager.uploadCarbs()
        async let healthKitUpload: () = provider.healthkitManager.uploadCarbs()
        async let tidepoolUpload: () = provider.tidepoolManager.uploadCarbs()

        _ = await [nightscoutUpload, healthKitUpload, tidepoolUpload]
    }

    // MARK: - Entry Loading

    /// Loads the values of a carb or FPU entry from Core Data
    /// - Parameter objectID: The ID of the entry to load
    /// - Returns: A tuple containing the entry's values, or nil if not found
    func loadEntryValues(from objectID: NSManagedObjectID) async
        -> (carbs: Decimal, fat: Decimal, protein: Decimal, note: String, date: Date)?
    {
        let context = CoreDataStack.shared.persistentContainer.viewContext

        return await context.perform {
            do {
                guard let entry = try context.existingObject(with: objectID) as? CarbEntryStored,
                      let entryDate = entry.date
                else { return nil }

                return (
                    carbs: Decimal(entry.carbs),
                    fat: Decimal(entry.fat),
                    protein: Decimal(entry.protein),
                    note: entry.note ?? "",
                    date: entryDate
                )
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to load entry: \(error)")
                return nil
            }
        }
    }

    // MARK: - FPU Entry Handling

    /// Handles the loading of FPU entries based on their type
    /// If the user taps on an FPU entry in the DataTable list, there are two cases:
    /// - the User has entered this FPU entry WITH carbs
    /// - the User has entered this FPU entry WITHOUT carbs
    /// In the first case, we simply need to load the corresponding carb entry. For this case THIS is the entry we want to edit.
    /// In the second case, we need to load the zero-carb entry that actually holds the FPU values (and the carbs). For this case THIS is the entry we want to edit.
    /// - Parameter objectID: The ID of the FPU entry
    /// - Returns: A tuple containing the entry values and ID, or nil if not found
    func handleFPUEntry(_ objectID: NSManagedObjectID) async
        -> (
            entryValues: (carbs: Decimal, fat: Decimal, protein: Decimal, note: String, date: Date)?,
            entryID: NSManagedObjectID?
        )?
    {
        // Case 1: FPU entry WITH carbs
        if let correspondingCarbEntryID = await getCorrespondingCarbEntry(objectID) {
            if let values = await loadEntryValues(from: correspondingCarbEntryID) {
                return (values, correspondingCarbEntryID)
            }
        }
        // Case 2: FPU entry WITHOUT carbs
        else if let originalEntryID = await getZeroCarbNonFPUEntry(objectID) {
            if let values = await loadEntryValues(from: originalEntryID) {
                return (values, originalEntryID)
            }
        }
        return nil
    }

    /// Retrieves the original zero-carb non-FPU entry for a given FPU entry.
    /// This is used when the user has entered a FPU entry WITHOUT carbs.
    /// - Parameter treatmentObjectID: The ID of the FPU entry
    /// - Returns: The ID of the original entry, or nil if not found
    func getZeroCarbNonFPUEntry(_ treatmentObjectID: NSManagedObjectID) async -> NSManagedObjectID? {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fpuContext"

        return await context.perform {
            do {
                // Get the fpuID from the selected entry
                guard let selectedEntry = try context.existingObject(with: treatmentObjectID) as? CarbEntryStored,
                      let fpuID = selectedEntry.fpuID
                else { return nil }

                // Fetch the original zero-carb entry (non-FPU) with the same fpuID
                let last24Hours = Date().addingTimeInterval(-60 * 60 * 24)
                let request = CarbEntryStored.fetchRequest()
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "date >= %@", last24Hours as NSDate),
                    NSPredicate(format: "fpuID == %@", fpuID as CVarArg),
                    NSPredicate(format: "isFPU == NO"),
                    NSPredicate(format: "carbs == 0")
                ])
                request.fetchLimit = 1

                let originalEntry = try context.fetch(request).first
                debugPrint("FPU fetch result: \(originalEntry != nil ? "Entry found" : "No entry found")")
                return originalEntry?.objectID

            } catch let error as NSError {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to fetch original FPU entry: \(error.userInfo)")
                return nil
            }
        }
    }

    /// Retrieves the corresponding carb entry for a given FPU entry.
    /// This is used when the user has entered a carb entry WITH FPUs all at once.
    /// - Parameter treatmentObjectID: The ID of the FPU entry
    /// - Returns: The ID of the corresponding carb entry, or nil if not found
    func getCorrespondingCarbEntry(_ treatmentObjectID: NSManagedObjectID) async -> NSManagedObjectID? {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "carbContext"

        return await context.perform {
            do {
                // Get the fpuID from the selected entry
                guard let selectedEntry = try context.existingObject(with: treatmentObjectID) as? CarbEntryStored,
                      let fpuID = selectedEntry.fpuID
                else { return nil }

                // Fetch the corresponding carb entry with the same fpuID
                let last24Hours = Date().addingTimeInterval(-24.hours.timeInterval)
                let request = CarbEntryStored.fetchRequest()
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "date >= %@", last24Hours as NSDate),
                    NSPredicate(format: "fpuID == %@", fpuID as CVarArg),
                    NSPredicate(format: "isFPU == NO"),
                    NSPredicate(format: "(carbs > 0) OR (fat > 0) OR (protein > 0)")
                ])
                request.fetchLimit = 1

                let correspondingCarbEntry = try context.fetch(request).first
                debugPrint(
                    "Corresponding carb entry fetch result: \(correspondingCarbEntry != nil ? "Entry found" : "No entry found")"
                )
                return correspondingCarbEntry?.objectID

            } catch let error as NSError {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to fetch corresponding carb entry: \(error.userInfo)")
                return nil
            }
        }
    }
}
