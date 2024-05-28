import CoreData
import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var apsManager: APSManager!
        @Injected() var unlockmanager: UnlockManager!
        @Injected() private var storage: FileStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
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

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            maxBolus = provider.pumpSettings().maxBolus
            broadcaster.register(DeterminationObserver.self, observer: self)
        }

        // Carb and FPU deletion from history
        /// marked as MainActor to be able to publish changes from the background
        /// - Parameter: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        @MainActor func invokeGlucoseDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await deleteGlucose(treatmentObjectID)
            }
        }

        func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async {
            let taskContext = CoreDataStack.shared.newTaskContext()
            taskContext.name = "deleteContext"
            taskContext.transactionAuthor = "deleteGlucose"

            var glucose: GlucoseStored?

            await taskContext.perform {
                do {
                    glucose = try taskContext.existingObject(with: treatmentObjectID) as? GlucoseStored

                    guard let glucoseToDelete = glucose else {
                        debugPrint("Data Table State: \(#function) \(DebuggingIdentifiers.failed) glucose not found in core data")
                        return
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

            guard let glucoseToDelete = glucose else {
                debugPrint(
                    "Data Table State: \(#function) \(DebuggingIdentifiers.failed) glucose not found after task context execution"
                )
                return
            }

            provider.deleteManualGlucose(date: glucoseToDelete.date)
        }

        // Carb and FPU deletion from history
        /// marked as MainActor to be able to publish changes from the background
        /// - Parameter: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        @MainActor func invokeCarbDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
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

                    if carbEntry.isFPU, let fpuID = carbEntry.id {
                        // fetch request for all carb entries with the same id
                        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CarbEntryStored.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", fpuID as CVarArg)

                        // NSBatchDeleteRequest
                        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                        deleteRequest.resultType = .resultTypeCount

                        // execute the batch delete request
                        let result = try taskContext.execute(deleteRequest) as? NSBatchDeleteResult
                        debugPrint("\(DebuggingIdentifiers.succeeded) Deleted \(result?.result ?? 0) items with FpuID \(fpuID)")

                        guard taskContext.hasChanges else { return }
                        try taskContext.save()

                    } else {
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

            // Delete carbs also from Nightscout and perform a determine basal sync to update cob
            if let carbEntry = carbEntry {
                provider.deleteCarbs(carbEntry)
                apsManager.determineBasalSync()
            }
        }

        // Insulin deletion from history
        /// marked as MainActor to be able to publish changes from the background
        /// - Parameter: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        @MainActor func invokeInsulinDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await deleteInsulin(treatmentObjectID)
                insulinEntryDeleted = true
                waitForSuggestion = true
            }
        }

        func deleteInsulin(_ treatmentObjectID: NSManagedObjectID) async {
            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    CoreDataStack.shared.deleteObject(identifiedBy: treatmentObjectID)

                    provider.deleteInsulin(with: treatmentObjectID)
                    apsManager.determineBasalSync()
                } else {
                    print("authentication failed")
                }
            } catch {
                print("authentication error: \(error.localizedDescription)")
            }
        }

        func addManualGlucose() {
            let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
            let glucoseAsInt = Int(glucose)
            let now = Date()
            let id = UUID().uuidString

            let saveToJSON = BloodGlucose(
                _id: id,
                direction: nil,
                date: Decimal(now.timeIntervalSince1970) * 1000,
                dateString: now,
                unfiltered: nil,
                filtered: nil,
                noise: nil,
                glucose: Int(glucose),
                type: GlucoseType.manual.rawValue
            )

            // TODO: -do we need this?
            // Save to Health
            var saveToHealth = [BloodGlucose]()
//            saveToHealth.append(saveToJSON)

            // save to core data
            coredataContext.perform {
                let newItem = GlucoseStored(context: self.coredataContext)
                newItem.id = UUID()
                newItem.date = Date()
                newItem.glucose = Int16(glucoseAsInt)
                newItem.isManual = true

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
