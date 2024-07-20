import CoreData
import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var apsManager: APSManager!
        @Injected() var unlockmanager: UnlockManager!
        @Injected() private var storage: FileStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
<<<<<<< HEAD
        @Injected() var healthKitManager: HealthKitManager!
=======
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

        let coredataContext = CoreDataStack.shared.newTaskContext()

        @Published var mode: Mode = .treatments
        @Published var treatments: [Treatment] = []
        @Published var glucose: [Glucose] = []
<<<<<<< HEAD
        @Published var meals: [Treatment] = []
        @Published var manualGlucose: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var waitForSuggestion: Bool = false
=======
        @Published var manualGlucose: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var externalInsulinAmount: Decimal = 0
        @Published var externalInsulinDate = Date()
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

        @Published var insulinEntryDeleted: Bool = false
        @Published var carbEntryDeleted: Bool = false

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units
            maxBolus = provider.pumpSettings().maxBolus
<<<<<<< HEAD
            broadcaster.register(DeterminationObserver.self, observer: self)
=======
            setupTreatments()
            setupGlucose()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(GlucoseObserver.self, observer: self)
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
        }

        // Carb and FPU deletion from history
        /// marked as MainActor to be able to publish changes from the background
        /// - Parameter: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
        @MainActor func invokeGlucoseDeletionTask(_ treatmentObjectID: NSManagedObjectID) {
            Task {
                await deleteGlucose(treatmentObjectID)
            }
        }

<<<<<<< HEAD
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
=======
                let carbs = self.provider.carbs()
                    .filter { !($0.isFPU ?? false) }
                    .map {
                        if let id = $0.id {
                            return Treatment(
                                units: units,
                                type: .carbs,
                                date: $0.createdAt,
                                amount: $0.carbs,
                                id: id,
                                note: $0.note
                            )
                        } else {
                            return Treatment(
                                units: units,
                                type: .carbs,
                                date: $0.createdAt,
                                amount: $0.carbs,
                                note: $0.note
                            )
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                        }
                    }

                    taskContext.delete(glucoseToDelete)

<<<<<<< HEAD
                    guard taskContext.hasChanges else { return }
                    try taskContext.save()
                    debugPrint("Data Table State: \(#function) \(DebuggingIdentifiers.succeeded) deleted glucose from core data")
                } catch {
                    debugPrint(
                        "Data Table State: \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose from core data: \(error.localizedDescription)"
=======
                let boluses = self.provider.pumpHistory()
                    .filter { $0.type == .bolus }
                    .map {
                        Treatment(
                            units: units,
                            type: .bolus,
                            date: $0.timestamp,
                            amount: $0.amount,
                            idPumpEvent: $0.id,
                            isSMB: $0.isSMB,
                            isExternal: $0.isExternalInsulin
                        )
                    }

                let tempBasals = self.provider.pumpHistory()
                    .filter { $0.type == .tempBasal || $0.type == .tempBasalDuration }
                    .chunks(ofCount: 2)
                    .compactMap { chunk -> Treatment? in
                        let chunk = Array(chunk)
                        guard chunk.count == 2, chunk[0].type == .tempBasal,
                              chunk[1].type == .tempBasalDuration else { return nil }
                        return Treatment(
                            units: units,
                            type: .tempBasal,
                            date: chunk[0].timestamp,
                            amount: chunk[0].rate ?? 0,
                            secondAmount: nil,
                            duration: Decimal(chunk[1].durationMin ?? 0)
                        )
                    }

                let tempTargets = self.provider.tempTargets()
                    .map {
                        Treatment(
                            units: units,
                            type: .tempTarget,
                            date: $0.createdAt,
                            amount: $0.targetBottom ?? 0,
                            secondAmount: $0.targetTop,
                            duration: $0.duration
                        )
                    }

                let suspend = self.provider.pumpHistory()
                    .filter { $0.type == .pumpSuspend }
                    .map {
                        Treatment(units: units, type: .suspend, date: $0.timestamp)
                    }

                let resume = self.provider.pumpHistory()
                    .filter { $0.type == .pumpResume }
                    .map {
                        Treatment(units: units, type: .resume, date: $0.timestamp)
                    }

                DispatchQueue.main.async {
                    self.treatments = [carbs, boluses, tempBasals, tempTargets, suspend, resume, fpus]
                        .flatMap { $0 }
                        .sorted { $0.date > $1.date }
                }
            }
        }

        func setupGlucose() {
            DispatchQueue.main.async {
                self.glucose = self.provider.glucose().map(Glucose.init)
            }
        }

        func deleteCarbs(_ treatment: Treatment) {
            provider.deleteCarbs(treatment)
        }

        func deleteInsulin(_ treatment: Treatment) {
            unlockmanager.unlock()
                .sink { _ in } receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.provider.deleteInsulin(treatment)
                }
                .store(in: &lifetime)
        }

        func deleteGlucose(_ glucose: Glucose) {
            let id = glucose.id
            provider.deleteGlucose(id: id)

            let fetchRequest: NSFetchRequest<NSFetchRequestResult>
            fetchRequest = NSFetchRequest(entityName: "Readings")
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: fetchRequest
            )
            deleteRequest.resultType = .resultTypeObjectIDs
            do {
                let deleteResult = try coredataContext.execute(deleteRequest) as? NSBatchDeleteResult
                if let objectIDs = deleteResult?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [coredataContext]
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
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

<<<<<<< HEAD
        func addManualGlucose() {
            let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
            let glucoseAsInt = Int(glucose)
=======
        func logManualGlucose() {
            let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
            let now = Date()
            let id = UUID().uuidString
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

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

        func logExternalInsulin() {
            guard externalInsulinAmount > 0 else {
                showModal(for: nil)
                return
            }

            externalInsulinAmount = min(externalInsulinAmount, maxBolus * 3) // Allow for 3 * Max Bolus for external insulin
            unlockmanager.unlock()
                .sink { _ in } receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    pumpHistoryStorage.storeEvents(
                        [
                            PumpHistoryEvent(
                                id: UUID().uuidString,
                                type: .bolus,
                                timestamp: externalInsulinDate,
                                amount: externalInsulinAmount,
                                duration: nil,
                                durationMin: nil,
                                rate: nil,
                                temp: nil,
                                carbInput: nil,
                                isExternalInsulin: true
                            )
                        ]
                    )
                    debug(.default, "External insulin saved to pumphistory.json")

                    // Reset amount to 0 for next entry
                    externalInsulinAmount = 0
                }
                .store(in: &lifetime)
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
