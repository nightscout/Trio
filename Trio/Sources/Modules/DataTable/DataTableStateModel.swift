import CoreData
import HealthKit
import Observation
import SwiftUI

extension DataTable {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var unlockmanager: UnlockManager!
        @ObservationIgnored @Injected() private var storage: FileStorage!
        @ObservationIgnored @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var healthKitManager: HealthKitManager!
        @ObservationIgnored @Injected() var carbsStorage: CarbsStorage!

        let coredataContext = CoreDataStack.shared.newTaskContext()

        var mode: Mode = .treatments
        var treatments: [Treatment] = []
        var manualGlucose: Decimal = 0
        var waitForSuggestion: Bool = false

        var insulinEntryDeleted: Bool = false
        var carbEntryDeleted: Bool = false

        var units: GlucoseUnits = .mgdL

        var carbEntryToEdit: CarbEntryStored?
        var showCarbEntryEditor = false

        override func subscribe() {
            units = settingsManager.settings.units
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
        }

        /// Checks if the glucose data is fresh based on the given date
        /// - Parameter glucoseDate: The date to check
        /// - Returns: Boolean indicating if the data is fresh
        func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool {
            glucoseStorage.isGlucoseDataFresh(glucoseDate)
        }

        /// Initiates the glucose deletion process asynchronously
        /// - Parameter treatmentObjectID: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        func invokeGlucoseDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await deleteGlucose(treatmentObjectID)
            }
        }

        func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async {
            // Delete from Apple Health/Tidepool
            await deleteGlucoseFromServices(treatmentObjectID)

            // Delete from Core Data
            await glucoseStorage.deleteGlucose(treatmentObjectID)
        }

        func deleteGlucoseFromServices(_ treatmentObjectID: NSManagedObjectID) async {
            let taskContext = CoreDataStack.shared.newTaskContext()
            taskContext.name = "deleteContext"
            taskContext.transactionAuthor = "deleteGlucoseFromServices"

            await taskContext.perform {
                do {
                    let result = try taskContext.existingObject(with: treatmentObjectID) as? GlucoseStored

                    guard let glucoseToDelete = result else {
                        debugPrint("Data Table State: \(#function) \(DebuggingIdentifiers.failed) glucose not found in core data")
                        return
                    }

                    // Delete from Nightscout
                    if let id = glucoseToDelete.id?.uuidString {
                        self.provider.deleteManualGlucoseFromNightscout(withID: id)
                    }

                    // Delete from Apple Health
                    if let id = glucoseToDelete.id?.uuidString {
                        self.provider.deleteGlucoseFromHealth(withSyncID: id)
                    }

                    debugPrint(
                        "\(#file) \(#function) \(DebuggingIdentifiers.succeeded) deleted glucose from remote service(s) (Nightscout, Apple Health, Tidepool)"
                    )
                } catch {
                    debugPrint(
                        "\(#file) \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose remote service(s) (Nightscout, Apple Health, Tidepool) with error: \(error)"
                    )
                }
            }
        }

        func addManualGlucose() {
            // Always save value in mg/dL
            let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
            let glucoseAsInt = Int(glucose)

            glucoseStorage.addManualGlucose(glucose: glucoseAsInt)
        }

        // Carb and FPU deletion from history
        /// - **Parameter**: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        func invokeCarbDeletionTask(_ treatmentObjectID: NSManagedObjectID, isFpuOrComplexMeal: Bool = false) {
            Task {
                do {
                    /// Set the variables that control the CustomProgressView BEFORE the actual deletion
                    /// otherwise the determineBasalSync gets executed first, sets waitForSuggestion to false and afterwards waitForSuggestion is set in this function to true, leading to an endless animation
                    await MainActor.run {
                        carbEntryDeleted = true
                        waitForSuggestion = true
                    }

                    try await deleteCarbs(treatmentObjectID, isFpuOrComplexMeal: isFpuOrComplexMeal)

                } catch {
                    debug(.default, "\(DebuggingIdentifiers.failed) Failed to delete carbs: \(error)")
                    await MainActor.run {
                        carbEntryDeleted = false
                        waitForSuggestion = false
                    }
                }
            }
        }

        func deleteCarbs(_ treatmentObjectID: NSManagedObjectID, isFpuOrComplexMeal: Bool = false) async throws {
            // Delete from Nightscout/Apple Health/Tidepool
            await deleteFromServices(treatmentObjectID, isFPUDeletion: isFpuOrComplexMeal)

            // Delete carbs from Core Data
            await carbsStorage.deleteCarbsEntryStored(treatmentObjectID)

            // Perform a determine basal sync to update cob
            try await apsManager.determineBasalSync()
        }

        /// Deletes carb and FPU entries from all connected services (Nightscout, HealthKit, Tidepool)
        /// - Parameters:
        ///   - treatmentObjectID: The Core Data object ID of the entry to delete
        ///   - isFPUDeletion: Flag indicating if this is a FPU deletion that requires special handling
        ///     - If true: Will first fetch the corresponding carb entry and then delete both FPU and carb entries
        ///     - If false: Will delete the entry directly as a standard carb deletion
        /// - Note: This function handles three scenarios:
        ///   1. Standard carb deletion (isFPUDeletion = false)
        ///   2. FPU-only deletion (isFPUDeletion = true)
        ///   3. Combined carb+FPU deletion (isFPUDeletion = true)
        func deleteFromServices(_ treatmentObjectID: NSManagedObjectID, isFPUDeletion: Bool = false) async {
            let taskContext = CoreDataStack.shared.newTaskContext()
            taskContext.name = "deleteContext"
            taskContext.transactionAuthor = "deleteCarbsFromServices"

            var carbEntry: CarbEntryStored?
            var objectIDToDelete = treatmentObjectID

            // For FPU deletions, first get the corresponding carb entry
            if isFPUDeletion {
                guard let correspondingEntry: (
                    entryValues: (carbs: Decimal, fat: Decimal, protein: Decimal, note: String, date: Date)?,
                    entryID: NSManagedObjectID?
                ) = await handleFPUEntry(treatmentObjectID),
                    let nsManagedObjectID = correspondingEntry.entryID
                else { return }

                objectIDToDelete = nsManagedObjectID
            }

            // Delete entries from all services
            await taskContext.perform {
                do {
                    carbEntry = try taskContext.existingObject(with: objectIDToDelete) as? CarbEntryStored
                    guard let carbEntry = carbEntry else {
                        debugPrint("Carb entry for deletion not found. \(DebuggingIdentifiers.failed)")
                        return
                    }

                    // Delete FPU related entries if they exist
                    if let fpuID = carbEntry.fpuID {
                        // Delete Fat and Protein entries from Nightscout
                        self.provider.deleteCarbsFromNightscout(withID: fpuID.uuidString)

                        // Delete Fat and Protein entries from Apple Health
                        let healthObjectsToDelete: [HKSampleType?] = [
                            AppleHealthConfig.healthFatObject,
                            AppleHealthConfig.healthProteinObject
                        ]

                        for sampleType in healthObjectsToDelete {
                            if let validSampleType = sampleType {
                                self.provider.deleteMealDataFromHealth(byID: fpuID.uuidString, sampleType: validSampleType)
                            }
                        }
                    }

                    // Delete carb entries if they exist
                    if let id = carbEntry.id, let entryDate = carbEntry.date {
                        self.provider.deleteCarbsFromNightscout(withID: id.uuidString)

                        // Delete carbs from Apple Health
                        if let sampleType = AppleHealthConfig.healthCarbObject {
                            self.provider.deleteMealDataFromHealth(byID: id.uuidString, sampleType: sampleType)
                        }

                        self.provider.deleteCarbsFromTidepool(
                            withSyncId: id,
                            carbs: Decimal(carbEntry.carbs),
                            at: entryDate,
                            enteredBy: CarbsEntry.local
                        )
                    }
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Error deleting entries: \(error)")
                }
            }
        }

        // Insulin deletion from history
        /// - **Parameter**: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        func invokeInsulinDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                do {
                    try await invokeInsulinDeletion(treatmentObjectID)
                } catch {
                    debug(.default, "\(DebuggingIdentifiers.failed) Failed to delete insulin entry: \(error)")
                }
            }
        }

        func invokeInsulinDeletion(_ treatmentObjectID: NSManagedObjectID) async throws {
            do {
                let authenticated = try await unlockmanager.unlock()

                guard authenticated else {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Authentication Error")
                    return
                }

                /// Set variables that control the CustomProgressView to true AFTER the authentication and BEFORE the actual determineBasalSync
                /// We definitely need to set the variables BEFORE the actual sync
                /// otherwise the determineBasalSync gets executed first, sets waitForSuggestion to false and afterwards waitForSuggestion is set in this function to true, leading to an endless animation
                /// But we also want it AFTER the authentication
                /// otherwise the animation would pop up even before the authentication prompt appears to the user
                await MainActor.run {
                    insulinEntryDeleted = true
                    waitForSuggestion = true
                }

                // Delete from remote service(s) (i.e. Nightscout, Apple Health, Tidepool)
                await deleteInsulinFromServices(with: treatmentObjectID)

                // Delete from Core Data
                await CoreDataStack.shared.deleteObject(identifiedBy: treatmentObjectID)

                // Perform a determine basal sync to update iob
                try await apsManager.determineBasalSync()
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Error while Insulin Deletion Task: \(error)"
                )
                await MainActor.run {
                    insulinEntryDeleted = false
                    waitForSuggestion = false
                }
            }
        }

        func deleteInsulinFromServices(with treatmentObjectID: NSManagedObjectID) async {
            let taskContext = CoreDataStack.shared.newTaskContext()
            taskContext.name = "deleteContext"
            taskContext.transactionAuthor = "deleteInsulinFromServices"

            await taskContext.perform {
                do {
                    guard let treatmentToDelete = try taskContext.existingObject(with: treatmentObjectID) as? PumpEventStored
                    else {
                        debug(.default, "Could not cast the object to PumpEventStored")
                        return
                    }

                    if let id = treatmentToDelete.id, let timestamp = treatmentToDelete.timestamp,
                       let bolus = treatmentToDelete.bolus, let bolusAmount = bolus.amount
                    {
                        self.provider.deleteInsulinFromNightscout(withID: id)
                        self.provider.deleteInsulinFromHealth(withSyncID: id)
                        self.provider.deleteInsulinFromTidepool(withSyncId: id, amount: bolusAmount as Decimal, at: timestamp)
                    }

                    taskContext.delete(treatmentToDelete)
                    try taskContext.save()

                    debug(.default, "Successfully deleted the treatment object.")
                } catch {
                    debug(.default, "Failed to delete the treatment object: \(error)")
                }
            }
        }

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
}

extension DataTable.StateModel: DeterminationObserver, SettingsObserver {
    func determinationDidUpdate(_: Determination) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
    }

    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
