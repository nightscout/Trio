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
        var historyLayout: HistoryLayout = .twoTabs

        override func subscribe() {
            units = settingsManager.settings.units
            maxBolus = provider.pumpSettings().maxBolus
            historyLayout = settingsManager.settings.historyLayout
            setupTreatments()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
        }

        private func setupTreatments() {
            DispatchQueue.global().async {
                let units = self.settingsManager.settings.units
                let carbs = self.provider.carbs()
                    .filter { !($0.isFPU ?? false) }
                    .map {
                        if let id = $0.id {
                            return Treatment(
                                units: units,
                                type: .carbs,
                                date: $0.actualDate ?? $0.createdAt,
                                amount: $0.carbs,
                                id: id,
                                fpuID: $0.fpuID,
                                note: $0.note
                            )
                        } else {
                            return Treatment(
                                units: units,
                                type: .carbs,
                                date: $0.actualDate ?? $0.createdAt,
                                amount: $0.carbs,
                                note: $0.note
                            )
                        }
                    }

                let fpus = self.provider.fpus()
                    .filter { $0.isFPU ?? false }
                    .map {
                        Treatment(
                            units: units,
                            type: .fpus,
                            date: $0.actualDate ?? $0.createdAt,
                            amount: $0.carbs,
                            id: $0.id,
                            isFPU: $0.isFPU,
                            fpuID: $0.fpuID,
                            note: $0.note
                        )
                    }

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
                            isExternal: $0.isExternal
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
                    if self.historyLayout == .threeTabs {
                        self.treatments = [boluses, tempBasals, tempTargets, suspend, resume]
                            .flatMap { $0 }
                            .sorted { $0.date > $1.date }
                        self.meals = [carbs, fpus]
                            .flatMap { $0 }
                            .sorted { $0.date > $1.date }
                    } else {
                        self.treatments = [carbs, fpus, boluses, tempBasals, tempTargets, suspend, resume]
                            .flatMap { $0 }
                            .sorted { $0.date > $1.date }
                    }
                }
            }
        }

        func invokeCarbDeletionTask(_ treatment: Treatment) {
            carbEntryDeleted = true
            waitForSuggestion = true
            deleteCarbs(treatment)
        }

        func deleteCarbs(_ treatment: Treatment) {
            provider.deleteCarbs(treatment)
            apsManager.determineBasalSync()
        }

        @MainActor func invokeInsulinDeletionTask(_ treatment: Treatment) {
            Task {
                do {
                    await deleteInsulin(treatment)
                    insulinEntryDeleted = true
                    waitForSuggestion = true
                }
            }
        }

        func deleteInsulin(_ treatment: Treatment) async {
            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    provider.deleteInsulin(treatment)
                    apsManager.determineBasalSync()
                } else {
                    print("authentication failed")
                }
            } catch {
                print("authentication error: \(error.localizedDescription)")
            }
        }

        func deleteGlucose(_ glucose: Glucose) {
            let id = glucose.id
            provider.deleteGlucose(id: id)

            let fetchRequest: NSFetchRequest<NSFetchRequestResult>
            fetchRequest = NSFetchRequest(entityName: "GlucoseStored")
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
                    )
                }
                debugPrint("Data Table State: \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) deleted glucose")
            } catch {
                debugPrint(
                    "Data Table State: \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to delete glucose"
                )
            }

            // Deletes Manual Glucose
            if (glucose.glucose.type ?? "") == GlucoseType.manual.rawValue {
                provider.deleteManualGlucose(date: glucose.glucose.dateString)
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
            provider.glucoseStorage.storeGlucose([saveToJSON])
            debug(.default, "Manual Glucose saved to glucose.json")
            // Save to Health
            var saveToHealth = [BloodGlucose]()
            saveToHealth.append(saveToJSON)

            // save to core data
            let newItem = GlucoseStored(context: coredataContext)
            newItem.id = UUID()
            newItem.date = Date()
            newItem.glucose = Int16(glucoseAsInt)
            newItem.isManual = true

            if coredataContext.hasChanges {
                do {
                    try coredataContext.save()
                    debugPrint(
                        "Data table state model: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) added manual glucose to core data"
                    )
                } catch {
                    debugPrint(
                        "Data table state model: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to add manual glucose to core data"
                    )
                }
            }
        }
    }
}

extension DataTable.StateModel:
    SettingsObserver,
    PumpHistoryObserver,
    TempTargetsObserver,
    CarbsObserver
{
    func settingsDidChange(_: FreeAPSSettings) {
        historyLayout = settingsManager.settings.historyLayout
        setupTreatments()
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupTreatments()
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTreatments()
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        setupTreatments()
    }
}

extension DataTable.StateModel: SuggestionObserver {
    func suggestionDidUpdate(_: Suggestion) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
    }
}
