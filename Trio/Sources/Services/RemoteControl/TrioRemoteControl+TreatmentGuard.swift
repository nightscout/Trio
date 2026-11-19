import CoreData
import Foundation
import LoopKit

extension TrioRemoteControl {
    func treatmentGuardContext(
        for payload: CommandPayload,
        objectIds: NightscoutObjectIdCache
    ) -> RemoteTreatmentGuard.Context {
        RemoteTreatmentGuard.Context(
            sendTime: Date(timeIntervalSince1970: payload.timestamp),
            now: Date(),
            knownThroughId: payload.knownThroughId,
            isNightscoutUploadEnabled: settings.settings.isUploadEnabled,
            markerRuleStart: objectIds.firstRecordedAt
        )
    }

    /// Boluses of every kind (manual, SMB, external, remote) dated at or after `date`.
    /// A bolus still in progress counts with its programmed amount.
    static func fetchTreatmentGuardBoluses(
        since date: Date,
        objectIds: NightscoutObjectIdCache,
        context: NSManagedObjectContext
    ) async throws -> [RemoteTreatmentGuard.StoredBolus] {
        try await context.perform {
            let request: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            request.predicate = NSPredicate(
                format: "type == %@ AND timestamp >= %@",
                PumpEventStored.EventType.bolus.rawValue,
                date as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            request.relationshipKeyPathsForPrefetching = ["bolus"]

            return try context.fetch(request).compactMap { event in
                guard let timestamp = event.timestamp, let bolus = event.bolus else { return nil }
                let candidate = RemoteTreatmentGuard.Candidate(
                    date: timestamp,
                    amount: RemoteTreatmentGuard.bolusUnits(
                        delivered: bolus.amount?.decimalValue ?? 0,
                        programmed: bolus.programmedAmount?.decimalValue ?? 0,
                        isInProgress: event.isMutable
                    ),
                    nightscoutId: event.id.flatMap(objectIds.objectId(forLocalId:))
                )
                return RemoteTreatmentGuard.StoredBolus(
                    candidate: candidate,
                    syncIdentifier: event.syncIdentifier,
                    isAutomatic: bolus.isSMB,
                    programmedUnits: bolus.programmedAmount?.decimalValue ?? bolus.amount?.decimalValue ?? 0
                )
            }
        }
    }

    /// Carb entries dated at or after `date`, including future-dated meals and carb equivalents.
    /// Carb equivalents are uploaded under their shared `fpuID`, and were created no later than their meal's date,
    /// which is their creation time when that meal is stored.
    static func fetchTreatmentGuardCarbEntries(
        since date: Date,
        objectIds: NightscoutObjectIdCache,
        context: NSManagedObjectContext
    ) async throws -> [RemoteTreatmentGuard.Candidate] {
        try await context.perform {
            let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let entries = try context.fetch(request)

            let fpuIds = Set(entries.filter(\.isFPU).compactMap(\.fpuID))
            var mealDates: [UUID: Date] = [:]
            if !fpuIds.isEmpty {
                let mealRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
                mealRequest.predicate = NSPredicate(format: "isFPU == NO AND fpuID IN %@", Array(fpuIds))
                for meal in try context.fetch(mealRequest) {
                    guard let fpuId = meal.fpuID, let mealDate = meal.date else { continue }
                    mealDates[fpuId] = min(mealDates[fpuId] ?? mealDate, mealDate)
                }
            }

            return entries.compactMap { entry in
                guard let entryDate = entry.date else { return nil }
                let localId = (entry.isFPU ? entry.fpuID : nil) ?? entry.id
                let mealDate = entry.isFPU ? entry.fpuID.flatMap { mealDates[$0] } : nil
                return RemoteTreatmentGuard.Candidate(
                    date: entryDate,
                    amount: NSNumber(value: entry.carbs).decimalValue,
                    nightscoutId: localId.flatMap { objectIds.objectId(forLocalId: $0.uuidString) },
                    createdAt: mealDate.map { min($0, entryDate) }
                )
            }
        }
    }

    /// The bolus the pump reports as being delivered.
    func pumpBolusInProgress() -> RemoteTreatmentGuard.InFlightBolus? {
        guard case let .inProgress(dose) = apsManager.pumpManager?.status.bolusState else { return nil }
        return RemoteTreatmentGuard.InFlightBolus(
            date: dose.startDate,
            units: NSNumber(value: dose.programmedUnits).decimalValue,
            syncIdentifier: dose.syncIdentifier,
            isAutomatic: dose.automatic ?? false
        )
    }

    /// Rejection message when `payload` was sent without knowledge of recent boluses or carb entries, otherwise nil.
    func treatmentGuardRejection(
        for payload: CommandPayload,
        bolusAmount: Decimal?,
        checkCarbs: Bool
    ) async throws -> String? {
        let objectIds = NightscoutObjectIdStore.shared.snapshot()
        let context = treatmentGuardContext(for: payload, objectIds: objectIds)

        if checkCarbs {
            let carbEntries = try await Self.fetchTreatmentGuardCarbEntries(
                since: context.lookbackStart,
                objectIds: objectIds,
                context: treatmentGuardStoreContext()
            )
            let decision = RemoteTreatmentGuard.evaluateCarbs(carbEntries: carbEntries, context: context)
            if let message = decision.rejectionMessage {
                return message
            }
        }

        if let bolusAmount = bolusAmount {
            let stored = try await Self.fetchTreatmentGuardBoluses(
                since: context.lookbackStart,
                objectIds: objectIds,
                context: treatmentGuardStoreContext()
            )
            let pumpBolus = pumpBolusInProgress()
            let pending = pendingRemoteBolus
            if let pending = pending, RemoteTreatmentGuard.activePendingBolus(
                pending,
                stored: stored,
                pumpBolusInProgress: pumpBolus,
                now: context.now
            ) == nil {
                clearPendingRemoteBolus(pending)
            }
            let boluses = RemoteTreatmentGuard.bolusCandidates(
                stored: stored,
                pumpBolusInProgress: pumpBolus,
                pendingRemoteBolus: pending,
                now: context.now
            )
            let decision = RemoteTreatmentGuard.evaluateBolus(requested: bolusAmount, boluses: boluses, context: context)
            if let message = decision.rejectionMessage {
                return message
            }
        }

        return nil
    }
}
