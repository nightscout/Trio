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
        var glucose: [Glucose] = []
        var meals: [Treatment] = []
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

        func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool {
            glucoseStorage.isGlucoseDataFresh(glucoseDate)
        }

        // Glucose deletion from history and from remote services
        /// -**Parameter**: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
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

        func updateCarbEntry(_ treatmentObjectID: NSManagedObjectID, newAmount: Decimal, newNote: String) {
            Task {
                // Update carb entry in Core Data
                await updateCarbEntryInCoreData(treatmentObjectID, newAmount: newAmount, newNote: newNote)

                // Perform a determine basal sync to keep data up to date
                await apsManager.determineBasalSync()

                // Delete carbs from Services
                await deleteCarbsFromServices(treatmentObjectID)

                // Upload updated carb entry to services in parallel
                async let nightscoutUpload: () = self.provider.nightscoutManager.uploadCarbs()
                async let healthKitUpload: () = self.provider.healthkitManager.uploadCarbs()
                async let tidepoolUpload: () = self.provider.tidepoolManager.uploadCarbs()

                // Wait for all uploads to complete
                _ = await [nightscoutUpload, healthKitUpload, tidepoolUpload]
            }
        }

        private func updateCarbEntryInCoreData(
            _ treatmentObjectID: NSManagedObjectID,
            newAmount: Decimal,
            newNote: String
        ) async {
            let context = CoreDataStack.shared.newTaskContext()
            context.name = "updateContext"
            context.transactionAuthor = "updateCarbEntry"

            await context.perform {
                do {
                    if let carbToUpdate = try context.existingObject(with: treatmentObjectID) as? CarbEntryStored {
                        carbToUpdate.carbs = Double(newAmount)
                        carbToUpdate.note = newNote
                        carbToUpdate.isUploadedToNS = false
                        carbToUpdate.isUploadedToHealth = false
                        carbToUpdate.isUploadedToTidepool = false

                        guard context.hasChanges else { return }
                        try context.save()

                        debugPrint(
                            "\(DebuggingIdentifiers.succeeded) Updated Carb Entry in Core Data"
                        )
                    }
                } catch {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) Error updating carb entry in Core Data with error: \(error.localizedDescription)"
                    )
                }
            }
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

        // Function to get the original zero-carb non-FPU entry
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

        func updateEntry(
            _ treatmentObjectID: NSManagedObjectID,
            newCarbs: Decimal,
            newFat: Decimal,
            newProtein: Decimal,
            newNote: String
        ) {
            Task {
                // Get the original entry's actualDate before deletion
                let context = CoreDataStack.shared.newTaskContext()

                let originalDate = await context.perform {
                    do {
                        guard let entry = try context.existingObject(with: treatmentObjectID) as? CarbEntryStored
                        else { return Date() }
                        return entry.date ?? Date()
                    } catch {
                        return Date()
                    }
                }

                // Delete old FPU from Core Data and Remote Services and await this
                await deleteCarbs(treatmentObjectID)

                // Create new FPU entry with updated values
                let newEntry = CarbsEntry(
                    id: UUID().uuidString,
                    createdAt: Date(),
                    actualDate: originalDate, // Use the original entry's date
                    carbs: newCarbs,
                    fat: newFat,
                    protein: newProtein,
                    note: newNote,
                    enteredBy: CarbsEntry.local,
                    isFPU: true,
                    fpuID: UUID().uuidString
                )

                // Store new entry which will create new FPU entries
                await carbsStorage.storeCarbs([newEntry], areFetchedFromRemote: false)

                // Upload updated entries to services in parallel
                async let nightscoutUpload: () = provider.nightscoutManager.uploadCarbs()
                async let healthKitUpload: () = provider.healthkitManager.uploadCarbs()
                async let tidepoolUpload: () = provider.tidepoolManager.uploadCarbs()

                // Wait for all uploads to complete
                _ = await [nightscoutUpload, healthKitUpload, tidepoolUpload]
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
