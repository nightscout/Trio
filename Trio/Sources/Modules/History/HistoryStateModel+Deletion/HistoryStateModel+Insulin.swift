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
}
