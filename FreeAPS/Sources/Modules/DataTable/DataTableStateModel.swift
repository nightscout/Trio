import CoreData
import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var apsManager: APSManager!
        @Injected() var unlockmanager: UnlockManager!
        @Injected() private var storage: FileStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var healthKitManager: HealthKitManager!

        let coredataContext = CoreDataStack.shared.newTaskContext()

        @Published var mode: Mode = .treatments
        @Published var treatments: [Treatment] = []
        @Published var glucose: [Glucose] = []
        @Published var meals: [Treatment] = []
        @Published var manualGlucose: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var waitForSuggestion: Bool = false

        @Published var insulinEntryDeleted: Bool = false
        @Published var carbEntryDeleted: Bool = false

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units
            maxBolus = provider.pumpSettings().maxBolus
            broadcaster.register(DeterminationObserver.self, observer: self)
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
            let taskContext = CoreDataStack.shared.newTaskContext()
            taskContext.name = "deleteContext"
            taskContext.transactionAuthor = "deleteGlucose"

            await taskContext.perform {
                do {
                    let result = try taskContext.existingObject(with: treatmentObjectID) as? GlucoseStored

                    guard let glucoseToDelete = result else {
                        debugPrint("Data Table State: \(#function) \(DebuggingIdentifiers.failed) glucose not found in core data")
                        return
                    }

                    // Delete Manual Glucose from Nightscout
                    if glucoseToDelete.isManual == true {
                        if let id = glucoseToDelete.id?.uuidString {
                            self.provider.deleteManualGlucoseFromNightscout(withID: id)
                        }
                    }

                    // Delete Glucose from Apple Health
                    if let id = glucoseToDelete.id?.uuidString {
                        self.provider.deleteGlucoseFromHealth(withSyncID: id)
                    }

                    taskContext.delete(glucoseToDelete)

                    guard taskContext.hasChanges else { return }
                    try taskContext.save()
                    debugPrint("Data Table State: \(#function) \(DebuggingIdentifiers.succeeded) deleted glucose from core data")
                } catch {
                    debugPrint(
                        "Data Table State: \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose from core data: \(error.localizedDescription)"
                    )
                }
            }
        }

        // Carb and FPU deletion from history
        /// - **Parameter**: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        func invokeCarbDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await deleteCarbs(treatmentObjectID)
                carbEntryDeleted = true
                waitForSuggestion = true
            }
        }

        func deleteCarbs(_ treatmentObjectID: NSManagedObjectID) async {
            let taskContext = CoreDataStack.shared.newTaskContext()
            taskContext.name = "deleteContext"
            taskContext.transactionAuthor = "deleteCarbs"

            var carbEntry: CarbEntryStored?

            await taskContext.perform {
                do {
                    carbEntry = try taskContext.existingObject(with: treatmentObjectID) as? CarbEntryStored
                    guard let carbEntry = carbEntry else {
                        debugPrint("Carb entry for batch delete not found. \(DebuggingIdentifiers.failed)")
                        return
                    }

                    if carbEntry.isFPU, let fpuID = carbEntry.fpuID {
                        // Delete FPUs from Nightscout
                        self.provider.deleteCarbsFromNightscout(withID: fpuID.uuidString)

                        // fetch request for all carb entries with the same id
                        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CarbEntryStored.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "fpuID == %@", fpuID as CVarArg)

                        // NSBatchDeleteRequest
                        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                        deleteRequest.resultType = .resultTypeCount

                        // execute the batch delete request
                        let result = try taskContext.execute(deleteRequest) as? NSBatchDeleteResult
                        debugPrint("\(DebuggingIdentifiers.succeeded) Deleted \(result?.result ?? 0) items with FpuID \(fpuID)")

                        Foundation.NotificationCenter.default.post(name: .didPerformBatchDelete, object: nil)
                    } else {
                        // Delete carbs from Nightscout
                        if let id = carbEntry.id?.uuidString {
                            self.provider.deleteCarbsFromNightscout(withID: id)
                        }

                        // Now delete carbs also from the Database
                        taskContext.delete(carbEntry)

                        guard taskContext.hasChanges else { return }
                        try taskContext.save()

                        debugPrint(
                            "Data Table State: \(#function) \(DebuggingIdentifiers.succeeded) deleted carb entry from core data"
                        )
                    }

                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Error deleting carb entry: \(error.localizedDescription)")
                }
            }

            // Perform a determine basal sync to update cob
            await apsManager.determineBasalSync()
        }

        // Insulin deletion from history
        /// - **Parameter**: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        func invokeInsulinDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await invokeInsulinDeletion(treatmentObjectID)
                insulinEntryDeleted = true
                waitForSuggestion = true
            }
        }

        func invokeInsulinDeletion(_ treatmentObjectID: NSManagedObjectID) async {
            do {
                let authenticated = try await unlockmanager.unlock()

                guard authenticated else {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Authentication Error")
                    return
                }

                async let deleteNSManagedObjectTask: () = CoreDataStack.shared.deleteObject(identifiedBy: treatmentObjectID)
                async let deleteInsulinTask: () = deleteInsulin(with: treatmentObjectID)

                await deleteNSManagedObjectTask
                await deleteInsulinTask

                // Perform a determine basal sync to update iob
                await apsManager.determineBasalSync()
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Error while Insulin Deletion Task: \(error.localizedDescription)"
                )
            }
        }

        func deleteInsulin(with treatmentObjectID: NSManagedObjectID) async {
            let taskContext = CoreDataStack.shared.newTaskContext()

            await taskContext.perform {
                do {
                    guard let treatmentToDelete = try taskContext.existingObject(with: treatmentObjectID) as? PumpEventStored
                    else {
                        debug(.default, "Could not cast the object to PumpEventStored")
                        return
                    }

                    // Delete Insulin from Nightscout
                    if let id = treatmentToDelete.id {
                        self.provider.deleteInsulinFromNightscout(withID: id)
                    }

                    // TODO: - Rewrite healthkit implementation

//                    let id = treatmentToDelete.id
//                    self.healthkitManager.deleteInsulin(syncID: id)

                    taskContext.delete(treatmentToDelete)
                    try taskContext.save()

                    debug(.default, "Successfully deleted the treatment object.")
                } catch {
                    debug(.default, "Failed to delete the treatment object: \(error.localizedDescription)")
                }
            }
        }

        func addManualGlucose() {
            let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
            let glucoseAsInt = Int(glucose)

            // save to core data
            coredataContext.perform {
                let newItem = GlucoseStored(context: self.coredataContext)
                newItem.id = UUID()
                newItem.date = Date()
                newItem.glucose = Int16(glucoseAsInt)
                newItem.isManual = true
                newItem.isUploadedToNS = false
                newItem.isUploadedToHealth = false

                do {
                    guard self.coredataContext.hasChanges else { return }
                    try self.coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
    }
}

extension DataTable.StateModel: DeterminationObserver {
    func determinationDidUpdate(_: Determination) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
    }
}
