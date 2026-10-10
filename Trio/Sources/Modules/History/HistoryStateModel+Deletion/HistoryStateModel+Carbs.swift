import CoreData
import Foundation

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

    /// Deletes the meal the tapped row belongs to from all services and Core Data, then refreshes COB.
    func deleteCarbs(_ treatmentObjectID: NSManagedObjectID, isFpuOrComplexMeal: Bool = false) async throws {
        var rootObjectID = treatmentObjectID
        if isFpuOrComplexMeal, let root = await handleFPUEntry(treatmentObjectID)?.entryID {
            rootObjectID = root
        }

        do {
            _ = try await carbEntryMutationService.deleteMeal(rootObjectID: rootObjectID)
        } catch let error as CarbEntryMutationError {
            // Orphaned rows have no resolvable root; remove them locally so they leave COB.
            debug(.default, "\(DebuggingIdentifiers.failed) Meal root unavailable (\(error)), deleting local rows only")
            await carbsStorage.deleteCarbsEntryStored(treatmentObjectID)
        }

        try await apsManager.determineBasalSync()
    }
}
