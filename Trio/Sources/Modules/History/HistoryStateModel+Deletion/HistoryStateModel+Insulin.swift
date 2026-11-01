import CoreData
import Foundation

extension History.StateModel {
    // Insulin deletion from history
    /// - **Parameter**: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
    func invokeInsulinDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
        Task {
            do {
                try await invokeInsulinDeletion(treatmentObjectID)
            } catch {
                warning(.treatments, "Insulin deletion task failed", error: error)
            }
        }
    }

    func invokeInsulinDeletion(_ treatmentObjectID: NSManagedObjectID) async throws {
        do {
            let authenticated = try await unlockmanager.unlock()

            guard authenticated else {
                debug(.treatments, "Insulin deletion not authenticated")
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
            warning(.treatments, "Deleting insulin entry failed", error: error)
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
                    warning(.treatments, "Insulin entry to delete not found")
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

                info(.treatments, "Insulin entry deleted")
            } catch {
                warning(.treatments, "Deleting insulin entry from storage failed", error: error)
            }
        }
    }
}
