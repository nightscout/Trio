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
        @Injected() var carbsStorage: CarbsStorage!

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
                            self.provider.deleteManualGlucose(withID: id)
                        }
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

            // Delete carbs or FPUs from Nightscout
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
                    } else {
                        // Delete carbs from Nightscout
                        if let id = carbEntry.id?.uuidString {
                            self.provider.deleteCarbsFromNightscout(withID: id)
                        }
                    }

                } catch {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) Error deleting carb entry from Nightscout: \(error.localizedDescription)"
                    )
                }
            }

            // Delete carbs from Core Data
            await carbsStorage.deleteCarbs(treatmentObjectID)

            // Perform a determine basal sync to update cob
            await apsManager.determineBasalSync()
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

                guard authenticated else {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Authentication Error")
                    return
                }

                async let deleteNSManagedObjectTask: () = CoreDataStack.shared.deleteObject(identifiedBy: treatmentObjectID)
                async let deleteInsulinFromNightScoutTask: () = provider.deleteInsulin(with: treatmentObjectID)
                async let determineBasalTask: () = apsManager.determineBasalSync()

                await deleteNSManagedObjectTask
                await deleteInsulinFromNightScoutTask
                await determineBasalTask

            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Error while Insulin Deletion Task: \(error.localizedDescription)"
                )
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
