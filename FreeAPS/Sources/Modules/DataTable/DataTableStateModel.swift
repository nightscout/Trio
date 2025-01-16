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
                        "\(#file) \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose remote service(s) (Nightscout, Apple Health, Tidepool) with error: \(error.localizedDescription)"
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
        func invokeCarbDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await deleteCarbs(treatmentObjectID)

                await MainActor.run {
                    carbEntryDeleted = true
                    waitForSuggestion = true
                }
            }
        }

        func deleteCarbs(_ treatmentObjectID: NSManagedObjectID) async {
            // Delete from Apple Health/Tidepool
            await deleteCarbsFromServices(treatmentObjectID)

            // Delete carbs from Core Data
            await carbsStorage.deleteCarbs(treatmentObjectID)

            // Perform a determine basal sync to update cob
            await apsManager.determineBasalSync()
        }

        func deleteCarbsFromServices(_ treatmentObjectID: NSManagedObjectID) async {
            let taskContext = CoreDataStack.shared.newTaskContext()
            taskContext.name = "deleteContext"
            taskContext.transactionAuthor = "deleteCarbsFromServices"

            var carbEntry: CarbEntryStored?

            // Delete carbs or FPUs from Nightscout
            await taskContext.perform {
                do {
                    carbEntry = try taskContext.existingObject(with: treatmentObjectID) as? CarbEntryStored
                    guard let carbEntry = carbEntry else {
                        debugPrint("Carb entry for deletion not found. \(DebuggingIdentifiers.failed)")
                        return
                    }

                    if carbEntry.isFPU, let fpuID = carbEntry.fpuID {
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
                    } else {
                        // Delete carbs from Nightscout
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
                    }

                } catch {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) Error deleting carb entry from remote service(s) (Nightscout, Apple Health, Tidepool) with error: \(error.localizedDescription)"
                    )
                }
            }
        }

        // Insulin deletion from history
        /// - **Parameter**: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        func invokeInsulinDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await invokeInsulinDeletion(treatmentObjectID)

                await MainActor.run {
                    insulinEntryDeleted = true
                    waitForSuggestion = true
                }
            }
        }

        func invokeInsulinDeletion(_ treatmentObjectID: NSManagedObjectID) async {
            do {
                let authenticated = try await unlockmanager.unlock()

                guard authenticated else {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Authentication Error")
                    return
                }

                // Delete from remote service(s) (i.e. Nightscout, Apple Health, Tidepool)
                await deleteInsulinFromServices(with: treatmentObjectID)

                // Delete from Core Data
                await CoreDataStack.shared.deleteObject(identifiedBy: treatmentObjectID)

                // Perform a determine basal sync to update iob
                await apsManager.determineBasalSync()
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Error while Insulin Deletion Task: \(error.localizedDescription)"
                )
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
                    debug(.default, "Failed to delete the treatment object: \(error.localizedDescription)")
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
        func updateEntry(
            _ treatmentObjectID: NSManagedObjectID,
            newCarbs: Decimal,
            newFat: Decimal,
            newProtein: Decimal,
            newNote: String
        ) {
            Task {
                let originalDate = await getOriginalEntryDate(treatmentObjectID)
                await updateEntryInCoreData(treatmentObjectID, newCarbs: newCarbs, newNote: newNote)
                await deleteOldAndCreateNewFPUEntry(
                    treatmentObjectID: treatmentObjectID,
                    originalDate: originalDate,
                    newCarbs: newCarbs,
                    newFat: newFat,
                    newProtein: newProtein,
                    newNote: newNote
                )
                await syncWithServices()
            }
        }

        /// Retrieves the original date of an entry and sets the isFPU flag
        /// - Parameter objectID: The ID of the entry
        /// - Returns: The original date or current date if not found
        private func getOriginalEntryDate(_ objectID: NSManagedObjectID) async -> Date {
            let context = CoreDataStack.shared.newTaskContext()
            context.name = "updateContext"
            context.transactionAuthor = "updateEntry"

            return await context.perform {
                do {
                    guard let entry = try context.existingObject(with: objectID) as? CarbEntryStored
                    else { return Date() }

                    /// Hacky workaround: Set isFPU flag to true before deletion
                    /// This is necessary because the deleteCarbs function in the CarbsStorage will fail if the isFPU flag is false and the entry won't get deleted.
                    entry.isFPU = true
                    try context.save()

                    return entry.date ?? Date()
                } catch {
                    return Date()
                }
            }
        }

        /// Updates a carb entry in Core Data
        /// The FPU entries are deleted and recreated. We don't need to do this for the carb entries as we can simply update the carb entry in Core Data.
        /// - Parameters:
        ///   - objectID: The ID of the entry to update
        ///   - newCarbs: The new carbs value
        ///   - newNote: The new note text
        private func updateEntryInCoreData(
            _ objectID: NSManagedObjectID,
            newCarbs: Decimal,
            newNote: String
        ) async {
            let context = CoreDataStack.shared.newTaskContext()

            await context.perform {
                do {
                    let entry = try context.existingObject(with: objectID) as? CarbEntryStored
                    entry?.carbs = Double(newCarbs)
                    entry?.note = newNote
                    try context.save()
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to update entry: \(error.localizedDescription)")
                }
            }
        }

        /// Deletes the old FPU entry and creates a new one with updated values
        /// - Parameters:
        ///   - treatmentObjectID: The ID of the entry to delete
        ///   - originalDate: The original date to preserve
        ///   - newCarbs: The new carbs value
        ///   - newFat: The new fat value
        ///   - newProtein: The new protein value
        ///   - newNote: The new note text
        private func deleteOldAndCreateNewFPUEntry(
            treatmentObjectID: NSManagedObjectID,
            originalDate: Date,
            newCarbs: Decimal,
            newFat: Decimal,
            newProtein: Decimal,
            newNote: String
        ) async {
            // Delete old FPU entry from Core Data and Remote Services and await this
            await deleteCarbs(treatmentObjectID)

            // Create new FPU entry
            let newEntry = CarbsEntry(
                id: UUID().uuidString,
                createdAt: Date(),
                actualDate: originalDate,
                carbs: newCarbs,
                fat: newFat,
                protein: newProtein,
                note: newNote,
                enteredBy: CarbsEntry.local,
                isFPU: true,
                fpuID: UUID().uuidString
            )

            await carbsStorage.storeCarbs([newEntry], areFetchedFromRemote: false)
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
            -> (carbs: Decimal, fat: Decimal, protein: Decimal, note: String)?
        {
            let context = CoreDataStack.shared.persistentContainer.viewContext

            return await context.perform {
                do {
                    guard let entry = try context.existingObject(with: objectID) as? CarbEntryStored else { return nil }
                    return (
                        carbs: Decimal(entry.carbs),
                        fat: Decimal(entry.fat),
                        protein: Decimal(entry.protein),
                        note: entry.note ?? ""
                    )
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to load entry: \(error.localizedDescription)")
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
            -> (entryValues: (carbs: Decimal, fat: Decimal, protein: Decimal, note: String)?, entryID: NSManagedObjectID?)?
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

    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
