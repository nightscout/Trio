import CoreData
import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var unlockmanager: UnlockManager!
        @Injected() private var storage: FileStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        @Published var mode: Mode = .treatments
        @Published var treatments: [Treatment] = []
        @Published var glucose: [Glucose] = []
        @Published var manualGlcuose: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var externalInsulinAmount: Decimal = 0
        @Published var externalInsulinDate = Date()

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            maxBolus = provider.pumpSettings().maxBolus
            setupTreatments()
            setupGlucose()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(GlucoseObserver.self, observer: self)
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
                        }
                    }

                let fpus = self.provider.fpus()
                    .filter { $0.isFPU ?? false }
                    .map {
                        Treatment(
                            units: units,
                            type: .fpus,
                            date: $0.createdAt,
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

        func deleteGlucose(at index: Int) {
            let id = glucose[index].id
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
                    )
                }
            } catch {
                // To do: handle any thrown errors.
            }
            // try? coredataContext.save()
        }

        func addManualGlucose() {
            let glucose = units == .mmolL ? manualGlcuose.asMgdL : manualGlcuose
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
                type: "Manual"
            )
            provider.glucoseStorage.storeGlucose([saveToJSON])
            debug(.default, "Manual Glucose saved to glucose.json")
        }

        func addExternalInsulin() {
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

extension DataTable.StateModel:
    SettingsObserver,
    PumpHistoryObserver,
    TempTargetsObserver,
    CarbsObserver,
    GlucoseObserver
{
    func settingsDidChange(_: FreeAPSSettings) {
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

    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }
}
