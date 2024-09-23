import CoreData
import HealthKit
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

            // Delete from Core Data
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
                                enteredBy: CarbsEntry.manual
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
                newItem.isUploadedToTidepool = false

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
