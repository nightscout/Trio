import CoreData
import Foundation
import HealthKit

extension History.StateModel {
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
}
