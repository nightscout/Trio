import CoreData
import Foundation

extension History.StateModel {
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
}
