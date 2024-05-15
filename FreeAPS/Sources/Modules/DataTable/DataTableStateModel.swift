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

        let coredataContext = CoreDataStack.shared.viewContext

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

        @MainActor func invokeGlucoseDeletionTask(_ glucose: GlucoseStored) {
            Task {
                do {
                    await deleteGlucose(glucose)
                    provider.deleteManualGlucose(date: glucose.date)
                }
            }
        }

        func deleteGlucose(_ glucose: GlucoseStored) async {
            do {
                coredataContext.delete(glucose)
                try coredataContext.save()
                debugPrint(
                    "Data Table State: \(#function) \(DebuggingIdentifiers.succeeded) deleted glucose from core data"
                )
            } catch {
                debugPrint(
                    "Data Table State: \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose from core data"
                )
            }
        }

        @MainActor func invokeCarbDeletionTask(_ treatment: CarbEntryStored) {
            Task {
                do {
                    await deleteCarbs(treatment)
                    carbEntryDeleted = true
                    waitForSuggestion = true
                }
            }
        }

        func deleteCarbs(_ carbEntry: CarbEntryStored) async {
            if carbEntry.isFPU, let fpuID = carbEntry.id {
                // fetch request for all carb entries with the same id
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CarbEntryStored.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", fpuID as CVarArg)

                // NSBatchDeleteRequest
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeCount

                do {
                    // execute the batch delete request
                    let result = try coredataContext.execute(deleteRequest) as? NSBatchDeleteResult
                    debugPrint("\(DebuggingIdentifiers.succeeded) Deleted \(result?.result ?? 0) items with FpuID \(fpuID)")

                    // merge changes from the database operation into the main context
                    if let objectIDs = (result?.result as? [NSManagedObjectID]) {
                        NSManagedObjectContext.mergeChanges(
                            fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                            into: [coredataContext]
                        )
                    }

                    try coredataContext.save()

                    provider.deleteCarbs(carbEntry)
                    apsManager.determineBasalSync()
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Error deleting FPU entries: \(error.localizedDescription)")
                }
            } else {
                do {
                    coredataContext.delete(carbEntry)
                    try coredataContext.save()
                    debugPrint(
                        "Data Table State: \(#function) \(DebuggingIdentifiers.succeeded) deleted carb entry from core data"
                    )
                } catch {
                    debugPrint(
                        "Data Table State: \(#function) \(DebuggingIdentifiers.failed) error while deleting carb entry from core data"
                    )
                }

                provider.deleteCarbs(carbEntry)
                apsManager.determineBasalSync()
            }
        }

        @MainActor func invokeInsulinDeletionTask(_ treatment: PumpEventStored) {
            Task {
                do {
                    await deleteInsulin(treatment)
                    insulinEntryDeleted = true
                    waitForSuggestion = true
                }
            }
        }

        func deleteInsulin(_ treatment: PumpEventStored) async {
            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    do {
                        coredataContext.delete(treatment)
                        try coredataContext.save()
                        debugPrint(
                            "Data Table State: \(#function) \(DebuggingIdentifiers.succeeded) deleted insulin from core data"
                        )
                    } catch {
                        debugPrint(
                            "Data Table State: \(#function) \(DebuggingIdentifiers.failed) error while deleting insulin from core data"
                        )
                    }

                    provider.deleteInsulin(treatment)
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
            saveToHealth.append(saveToJSON)

            // save to core data
            coredataContext.perform {
                let newItem = GlucoseStored(context: self.coredataContext)
                newItem.id = UUID()
                newItem.date = Date()
                newItem.glucose = Int16(glucoseAsInt)
                newItem.isManual = true

                do {
                    try CoreDataStack.shared.viewContext.saveContext()
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
