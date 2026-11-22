import Combine
import CoreData
import Foundation
import LoopKit
import SwiftDate
import Swinject

protocol PumpHistoryObserver {
    func pumpHistoryDidUpdate(_ events: [PumpHistoryEvent])
}

struct PumpSuspensionReconciliation: Equatable {
    let didReconcile: Bool
    let purgedUploadedIds: [String]

    static let unchanged = PumpSuspensionReconciliation(didReconcile: false, purgedUploadedIds: [])
}

protocol PumpHistoryStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    func getPumpHistory() async throws -> [PumpHistoryEvent]
    /// Returns the ids of purged events that were already uploaded to NS,
    /// so the caller can delete the now-withdrawn treatments remotely.
    @discardableResult func storePumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool) async throws -> [String]
    /// Closes or re-anchors a trailing `PumpSuspend` when post-suspend pump delivery or a fresh
    /// pump sync confirms basal delivery is active, covering pump-side resumes that write no
    /// history record (cancelled fixed prime on Medtronic, clock reset across a battery change,
    /// or pod/patch replacement).
    @discardableResult func reconcileOpenSuspension(
        activeDeliverySince: Date?,
        lastVerifiedSyncDate: Date?,
        now: Date
    ) async throws -> PumpSuspensionReconciliation
    func storeExternalInsulinEvent(amount: Decimal, timestamp: Date) async
    func getPumpHistoryNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getPumpHistoryNotYetUploadedToHealth() async throws -> [PumpHistoryEvent]
    func getPumpHistoryNotYetUploadedToTidepool() async throws -> [PumpHistoryEvent]
}

extension PumpHistoryStorage {
    @discardableResult func reconcileOpenSuspension(
        activeDeliverySince: Date?,
        lastVerifiedSyncDate: Date?,
        now: Date
    ) async throws -> PumpSuspensionReconciliation {
        .unchanged
    }

    @discardableResult func reconcileOpenSuspension(
        activeDeliverySince: Date?,
        now: Date = Date()
    ) async throws -> PumpSuspensionReconciliation {
        try await reconcileOpenSuspension(
            activeDeliverySince: activeDeliverySince,
            lastVerifiedSyncDate: nil,
            now: now
        )
    }
}

final class BasePumpHistoryStorage: PumpHistoryStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BasePumpHistoryStorage.processQueue")
    private let bufferedConfirmationsLock = NSLock()
    private var bufferedStatusDates: [Date] = []
    @Injected() var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    let makeContext: () -> NSManagedObjectContext

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        injectServices(resolver)
    }

    typealias PumpEvent = PumpEventStored.EventType
    typealias TempType = PumpEventStored.TempType

    private func roundDose(_ dose: Double, toIncrement increment: Double) -> Decimal {
        let roundedValue = (dose / increment).rounded() * increment
        return Decimal(roundedValue)
    }

    /// Dose-time snapshot of the active insulin model; never revised on finalization.
    private func applyInsulinSnapshot(to event: PumpEventStored, insulinType: InsulinType?) {
        let preferences = settings.preferences
        event.insulinType = insulinType?.identifier
        event.actionDuration = settings.pumpSettings.insulinActionCurve as NSDecimalNumber
        event.peakTime = IobCalculation.lookupPeak(
            curve: preferences.curve,
            useCustomPeakTime: preferences.useCustomPeakTime,
            insulinPeakTime: preferences.insulinPeakTime
        ).map { Decimal($0) as NSDecimalNumber }
    }

    @discardableResult func storePumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool) async throws -> [String] {
        let context = makeContext()
        context.name = "storePumpEvents"
        // on constraint conflicts the persisted row wins: finalized rows never change
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        return try await context.perform {
            let candidates = events.flatMap(Self.storedCandidates(for:))
            // upsert candidates: dose syncIdentifier, timestamp+type as fallback
            // LoopKit derives dose.syncIdentifier from raw; empty raw must not become a shared identity
            let syncIdentifiers = candidates.compactMap(\.syncIdentifier)
            let timestamps = candidates.map(\.date)
            let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "syncIdentifier IN %@", syncIdentifiers),
                NSPredicate(format: "timestamp IN %@", timestamps)
            ])
            request.relationshipKeyPathsForPrefetching = ["tempBasal"]
            let existingRows = try context.fetch(request)

            var bySyncIdentifier = Dictionary(
                existingRows.compactMap { row in row.syncIdentifier.map { ($0, row) } },
                uniquingKeysWith: { first, _ in first }
            )
            var byTimestampAndType = Dictionary(
                existingRows.map { row in
                    (
                        TimestampAndType(
                            timestamp: row.timestamp ?? .distantPast,
                            type: row.type ?? "",
                            isScheduledBasal: row.tempBasal?.isScheduledBasal ?? false
                        ),
                        row
                    )
                },
                uniquingKeysWith: { first, _ in first }
            )

            var assertedRows = Set<NSManagedObjectID>()
            var harvestedStatusDates: [Date] = []

            for candidate in candidates {
                let event = candidate.event
                let storedType = candidate.storedType

                // Type-aware key: same-timestamp bolus + TBR no longer shadow each other. Scheduled
                // basal needs its own dimension on top, because it also stores as a TBR row and a
                // pump cancelling a temp basal reports both at the very same second — Medtronic
                // resumes the schedule the instant a temp ends. Without this a schedule report
                // hijacks the still-mutable cancel row and inherits its non-scheduled identity.
                let fallbackKey = TimestampAndType(
                    timestamp: candidate.date,
                    type: storedType.rawValue,
                    isScheduledBasal: candidate.isScheduledBasal
                )
                let syncIdentifier = candidate.syncIdentifier
                let match = syncIdentifier.flatMap { bySyncIdentifier[$0] }
                    ?? byTimestampAndType[fallbackKey]

                if let match = match {
                    if Self.isReconciledResume(match), storedType == .pumpResume {
                        // Harvest and retain recorded live-status confirmations (and any pending
                        // Nightscout re-upload marker) when promoting the row to hardware provenance.
                        let preservedDates = Self.statusConfirmedDates(of: match)
                        let keepNightscoutReupload = Self.needsNightscoutReupload(match)
                        let keepReplacedIds = Self.replacedDerivedIds(of: match)
                        harvestedStatusDates.append(contentsOf: preservedDates)
                        if let previousSyncId = match.syncIdentifier {
                            bySyncIdentifier.removeValue(forKey: previousSyncId)
                        }
                        match.syncIdentifier = syncIdentifier
                        match.note = Self.encodeReconciledNote(
                            statusDates: preservedDates,
                            needsNightscoutReupload: keepNightscoutReupload,
                            replacedIds: keepReplacedIds
                        )
                        if let syncIdentifier {
                            bySyncIdentifier[syncIdentifier] = match
                        }
                    }
                    assertedRows.insert(match.objectID)
                    // finalized rows never change
                    if match.isMutable, let dose = event.dose {
                        self.updateMutablePumpEvent(match, with: dose)
                    }
                    continue
                }

                let newPumpEvent = PumpEventStored(context: context)
                newPumpEvent.id = UUID().uuidString
                // restrict entry to now or past
                newPumpEvent.timestamp = min(candidate.date, Date())
                newPumpEvent.type = storedType.rawValue
                newPumpEvent.syncIdentifier = syncIdentifier
                newPumpEvent.isMutable = event.dose?.isMutable ?? false
                newPumpEvent.isUploadedToNS = false
                newPumpEvent.isUploadedToHealth = false
                newPumpEvent.isUploadedToTidepool = false
                if let dose = event.dose {
                    self.applyInsulinSnapshot(to: newPumpEvent, insulinType: dose.insulinType)
                }

                switch storedType {
                case .bolus:
                    guard let dose = event.dose else {
                        context.delete(newPumpEvent)
                        continue
                    }
                    let newBolusEntry = BolusStored(context: context)
                    newBolusEntry.pumpEvent = newPumpEvent
                    newBolusEntry.amount = NSDecimalNumber(decimal: self.roundDose(
                        dose.unitsInDeliverableIncrements,
                        toIncrement: Double(self.settings.preferences.bolusIncrement)
                    ))
                    newBolusEntry.programmedAmount = NSDecimalNumber(decimal: self.roundDose(
                        dose.programmedUnits,
                        toIncrement: Double(self.settings.preferences.bolusIncrement)
                    ))
                    newBolusEntry.isExternal = dose.manuallyEntered
                    newBolusEntry.isProgrammedByPumpUI = dose.wasProgrammedByPumpUI
                    newBolusEntry.isSMB = dose.automatic ?? true

                case .tempBasal:
                    guard let dose = event.dose else {
                        context.delete(newPumpEvent)
                        continue
                    }
                    let newTempBasal = TempBasalStored(context: context)
                    let isScheduledBasal = candidate.isScheduledBasal
                    let span = Self.storedSpan(of: dose, isScheduledBasal: isScheduledBasal)
                    newTempBasal.pumpEvent = newPumpEvent
                    newTempBasal.duration = span.duration
                    newTempBasal.rate = Decimal(dose.unitsPerHour) as NSDecimalNumber
                    newTempBasal.startDate = span.start
                    newTempBasal.endDate = span.end
                    newTempBasal.deliveredUnits = dose.deliveredUnits.map { Decimal($0) as NSDecimalNumber }
                    newTempBasal.tempType = TempType.absolute.rawValue
                    newTempBasal.isScheduledBasal = isScheduledBasal

                case .pumpAlarm:
                    newPumpEvent.note = event.title

                default:
                    break
                }

                // same-batch dedup
                if let syncIdentifier = newPumpEvent.syncIdentifier {
                    bySyncIdentifier[syncIdentifier] = newPumpEvent
                }
                byTimestampAndType[fallbackKey] = newPumpEvent
                assertedRows.insert(newPumpEvent.objectID)
            }

            // Mutable rows are the pump's assertions (LoopKit contract): a
            // complete pending report supersedes any it no longer contains.
            var purgedUploadedIds: [String] = []
            var purgedOrphanDates: [Date] = []
            if replacePendingEvents {
                let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
                request.predicate = NSPredicate(format: "isMutable == YES")
                for orphan in try context.fetch(request) where !assertedRows.contains(orphan.objectID) {
                    debug(
                        .storage,
                        "Purging stale pending pump event \(orphan.syncIdentifier ?? orphan.id ?? "-") (\(orphan.type ?? "?")), uploaded to Nightscout: \(orphan.isUploadedToNS)"
                    )
                    if let timestamp = orphan.timestamp {
                        purgedOrphanDates.append(timestamp)
                    }
                    if orphan.isUploadedToNS, let id = orphan.id {
                        purgedUploadedIds.append(id)
                    }
                    context.delete(orphan)
                }
            }

            let storeNow = Date()
            let earliestTouchedDate = (candidates.map(\.date) + purgedOrphanDates).min() ?? storeNow
            let lookbackStart = min(
                storeNow.addingTimeInterval(-48.hours.timeInterval),
                earliestTouchedDate.addingTimeInterval(-1.hours.timeInterval)
            )
            let priorBufferedDates = self.bufferedConfirmationsLock.withLock { self.bufferedStatusDates }
            var remainingUnpersistedDates = priorBufferedDates
            _ = try Self.reconcileSuspensions(
                in: context,
                lookbackStart: lookbackStart,
                activeDeliverySince: nil,
                lastVerifiedSyncDate: nil,
                extraStatusDates: harvestedStatusDates + priorBufferedDates,
                allowNewTrailingResume: false,
                now: storeNow,
                purgedUploadedIds: &purgedUploadedIds,
                unpersistedStatusDates: &remainingUnpersistedDates
            )

            do {
                if context.hasChanges {
                    try context.save()
                    self.bufferedConfirmationsLock.withLock {
                        self.bufferedStatusDates = remainingUnpersistedDates
                    }
                    self.updateSubject.send(())
                    debug(.storage, "Stored pump events")
                } else {
                    self.bufferedConfirmationsLock.withLock {
                        self.bufferedStatusDates = remainingUnpersistedDates
                    }
                }
            } catch let error as NSError {
                warning(.storage, "Storing pump events failed", error: error)
                throw error
            }
            return purgedUploadedIds
        }
    }

    @discardableResult func reconcileOpenSuspension(
        activeDeliverySince: Date?,
        lastVerifiedSyncDate: Date? = nil,
        now: Date = Date()
    ) async throws -> PumpSuspensionReconciliation {
        let context = makeContext()
        context.name = "reconcileOpenSuspension"
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        return try await context.perform {
            var purgedUploadedIds: [String] = []
            let priorBufferedDates = self.bufferedConfirmationsLock.withLock { self.bufferedStatusDates }
            var remainingUnpersistedDates = priorBufferedDates
            let didMutateTimeline = try Self.reconcileSuspensions(
                in: context,
                lookbackStart: now.addingTimeInterval(-48.hours.timeInterval),
                activeDeliverySince: activeDeliverySince,
                lastVerifiedSyncDate: lastVerifiedSyncDate,
                extraStatusDates: priorBufferedDates,
                allowNewTrailingResume: true,
                now: now,
                purgedUploadedIds: &purgedUploadedIds,
                unpersistedStatusDates: &remainingUnpersistedDates
            )
            if context.hasChanges {
                try context.save()
            }
            self.bufferedConfirmationsLock.withLock {
                self.bufferedStatusDates = remainingUnpersistedDates
            }
            guard didMutateTimeline else { return .unchanged }
            self.updateSubject.send(())
            debug(.storage, "Reconciled pump suspensions up to \(now)")
            return PumpSuspensionReconciliation(didReconcile: true, purgedUploadedIds: purgedUploadedIds)
        }
    }

    /// Span to persist for a basal dose.
    ///
    /// A pump-reported scheduled basal has no end: the pump asserts a rate that runs until
    /// something supersedes it. Drivers spell that differently — DanaKit, MedtrumKit and
    /// TandemKit report a zero-length dose, MinimedKit a 24 h placeholder whose "true duration
    /// will be reconciled against other entries" (MinimedKit `DoseStore.swift`). Neither is a
    /// delivery span, so scheduled basal is stored open-ended and consumers resolve it against
    /// the next event.
    private static func storedSpan(
        of dose: DoseEntry,
        isScheduledBasal: Bool
    ) -> (duration: Int16, start: Date, end: Date) {
        guard !isScheduledBasal else { return (0, dose.startDate, dose.startDate) }
        return (
            Int16(round((dose.endDate - dose.startDate).timeInterval / 60)),
            dose.startDate,
            dose.endDate
        )
    }

    /// Finalized reports freeze the row with delivered values. If NS-visible
    /// values changed on an already-uploaded row, the upload flag resets and
    /// the re-POST replaces the NS document in place.
    private func updateMutablePumpEvent(_ event: PumpEventStored, with dose: DoseEntry) {
        switch event.type {
        case PumpEventStored.EventType.bolus.rawValue:
            guard let bolus = event.bolus else { return }
            let previousAmount = bolus.amount
            let previousProgrammedByPumpUI = bolus.isProgrammedByPumpUI
            let finalAmount = dose.deliveredUnits.map {
                self.roundDose($0, toIncrement: Double(settings.preferences.bolusIncrement))
            }
            if let finalAmount = finalAmount {
                bolus.amount = finalAmount as NSDecimalNumber
            }
            bolus.isSMB = dose.automatic ?? true
            bolus.isProgrammedByPumpUI = dose.wasProgrammedByPumpUI
            event.isMutable = dose.isMutable
            if event.isUploadedToNS,
               bolus.amount != previousAmount || bolus.isProgrammedByPumpUI != previousProgrammedByPumpUI
            {
                event.isUploadedToNS = false
            }
            if !dose.isMutable {
                debug(.pump, "Finalized bolus \(dose.syncIdentifier ?? "-"): \(bolus.amount ?? 0) U")
            }

        case PumpEventStored.EventType.tempBasal.rawValue:
            guard let tempBasal = event.tempBasal else { return }
            let previousRate = tempBasal.rate
            let previousDuration = tempBasal.duration
            // The dose says what this is; the row's own flag is stale exactly when it matters,
            // and reading it back would let a schedule report keep a temp basal's identity —
            // and with it a 24 h placeholder span read as delivery.
            let isScheduledBasal = dose.type == .basal
            let span = Self.storedSpan(of: dose, isScheduledBasal: isScheduledBasal)
            tempBasal.isScheduledBasal = isScheduledBasal
            tempBasal.duration = span.duration
            tempBasal.rate = Decimal(dose.unitsPerHour) as NSDecimalNumber
            tempBasal.startDate = span.start
            tempBasal.endDate = span.end
            tempBasal.deliveredUnits = dose.deliveredUnits.map { Decimal($0) as NSDecimalNumber }
            event.isMutable = dose.isMutable
            if event.isUploadedToNS, tempBasal.rate != previousRate || tempBasal.duration != previousDuration {
                event.isUploadedToNS = false
            }
            if !dose.isMutable {
                debug(
                    .pump,
                    "Finalized temp basal \(dose.syncIdentifier ?? "-"): rate \(tempBasal.rate ?? 0) U/h for \(tempBasal.duration) min"
                )
            }

        default:
            // non-dose rows have no revisable payload
            event.isMutable = dose.isMutable
        }
    }

    func storeExternalInsulinEvent(amount: Decimal, timestamp: Date) async {
        let context = makeContext()
        context.name = "storeExternalInsulinEvent"
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        await context.perform {
            // create pump event
            let newPumpEvent = PumpEventStored(context: context)
            let identifier = UUID().uuidString
            newPumpEvent.id = identifier
            // Trio-created record: it is its own source of truth, born final.
            newPumpEvent.syncIdentifier = identifier
            newPumpEvent.isMutable = false
            // restrict entry to now or past
            newPumpEvent.timestamp = timestamp > Date() ? Date() : timestamp
            newPumpEvent.type = PumpEvent.bolus.rawValue
            newPumpEvent.isUploadedToNS = false
            newPumpEvent.isUploadedToHealth = false
            newPumpEvent.isUploadedToTidepool = false

            // create bolus entry and specify relationship to pump event
            let newBolusEntry = BolusStored(context: context)
            newBolusEntry.pumpEvent = newPumpEvent
            newBolusEntry.amount = amount as NSDecimalNumber
            newBolusEntry.programmedAmount = amount as NSDecimalNumber
            newBolusEntry.isExternal = true // we are creating an external dose
            newBolusEntry.isSMB = false // the dose is manually administered

            do {
                guard context.hasChanges else { return }
                try context.save()
                debug(.storage, "Saved external insulin \(amount) U")
                self.updateSubject.send(())
            } catch {
                warning(.storage, "Saving external insulin failed", error: error)
            }
        }
    }

    func getPumpHistory() async throws -> [PumpHistoryEvent] {
        let context = makeContext()
        context.name = "getPumpHistory"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: false,
            relationshipKeyPathsForPrefetching: ["bolus", "tempBasal"]
        )

        return await context.perform {
            guard let fetchedPumpEvents = results as? [PumpEventStored] else { return [] }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEventStored.EventType.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?
                    )
                case PumpEventStored.EventType.tempBasal.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .tempBasal,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.tempBasal?.rate as Decimal?,
                        duration: Int(event.tempBasal?.duration ?? 0),
                        isScheduledBasal: event.tempBasal?.isScheduledBasal ?? false,
                        deliveredUnits: event.tempBasal?.deliveredUnits as Decimal?
                    )
                // TDD and scheduled-basal inference need suspension spans
                case PumpEventStored.EventType.pumpSuspend.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .pumpSuspend,
                        timestamp: event.timestamp ?? Date()
                    )
                case PumpEventStored.EventType.pumpResume.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .pumpResume,
                        timestamp: event.timestamp ?? Date()
                    )
                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func determineBolusEventType(for event: PumpEventStored) -> PumpEventStored.EventType {
        guard let bolus = event.bolus else {
            return event.type.flatMap({ PumpEventStored.EventType(rawValue: $0) }) ?? .bolus
        }
        if bolus.isSMB {
            return .smb
        }
        if bolus.isExternal {
            return .isExternal
        }
        return event.type.flatMap({ PumpEventStored.EventType(rawValue: $0) }) ?? .bolus
    }

    func getPumpHistoryNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let context = makeContext()
        context.name = "getPumpHistoryNotYetUploadedToNightscout"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToNightscout,
            key: "timestamp",
            ascending: false,
            relationshipKeyPathsForPrefetching: ["bolus", "tempBasal"]
        )

        return try await context.perform { [self] in
            guard let fetchedPumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    // eventType determines whether bolus is external, smb or manual (=administered via app by user)
                    let eventType = determineBolusEventType(for: event)
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: eventType,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: event.bolus?.amount as Decimal?,
                        notes: nil,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil,
                        id: event.id,
                        // omitted unless set, like LoopKit's DoseEntry encoding
                        isProgrammedByPumpUI: event.bolus?.isProgrammedByPumpUI == true ? true : nil
                    )
                case PumpEvent.tempBasal.rawValue:
                    return NightscoutTreatment(
                        duration: Int(event.tempBasal?.duration ?? 0),
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: event.tempBasal?.rate as Decimal?,
                        rate: event.tempBasal?.rate as Decimal?,
                        eventType: .nsTempBasal,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: nil,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil,
                        id: event.id
                    )
                case PumpEvent.pumpSuspend.rawValue:
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsNote,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: PumpEvent.pumpSuspend.rawValue,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )
                case PumpEvent.pumpResume.rawValue:
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsNote,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: PumpEvent.pumpResume.rawValue,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil,
                        id: event.id
                    )
                case PumpEvent.rewind.rawValue:
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsInsulinChange,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: nil,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )
                case PumpEvent.siteChange.rawValue:
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsSiteChange,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: nil,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )
                case PumpEvent.pumpAlarm.rawValue:
                    return NightscoutTreatment(
                        duration: 30, // minutes
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsAnnouncement,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: "Alarm \(String(describing: event.note)) \(PumpEvent.pumpAlarm.rawValue)",
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )

                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func getPumpHistoryNotYetUploadedToHealth() async throws -> [PumpHistoryEvent] {
        let context = makeContext()
        context.name = "getPumpHistoryNotYetUploadedToHealth"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToHealth,
            key: "timestamp",
            ascending: false,
            relationshipKeyPathsForPrefetching: ["bolus", "tempBasal"]
        )

        return try await context.perform {
            guard let fetchedPumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?,
                        isExternal: event.bolus?.isExternal ?? false,
                        insulinType: event.insulinType
                    )
                case PumpEvent.tempBasal.rawValue:
                    if let id = event.id, let timestamp = event.timestamp, let tempBasal = event.tempBasal,
                       let tempBasalRate = tempBasal.rate
                    {
                        return PumpHistoryEvent(
                            id: id,
                            type: .tempBasal,
                            timestamp: timestamp,
                            amount: tempBasalRate as Decimal,
                            duration: Int(tempBasal.duration),
                            deliveredUnits: tempBasal.deliveredUnits as Decimal?,
                            insulinType: event.insulinType
                        )
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func getPumpHistoryNotYetUploadedToTidepool() async throws -> [PumpHistoryEvent] {
        let context = makeContext()
        context.name = "getPumpHistoryNotYetUploadedToTidepool"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToTidepool,
            key: "timestamp",
            ascending: false,
            relationshipKeyPathsForPrefetching: ["bolus", "tempBasal"]
        )

        return try await context.perform {
            guard let fetchedPumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?,
                        isSMB: event.bolus?.isSMB ?? true,
                        isExternal: event.bolus?.isExternal ?? false,
                        programmedAmount: event.bolus?.programmedAmount as Decimal?,
                        insulinType: event.insulinType
                    )
                case PumpEvent.tempBasal.rawValue:
                    if let id = event.id, let timestamp = event.timestamp, let tempBasal = event.tempBasal,
                       let tempBasalRate = tempBasal.rate
                    {
                        return PumpHistoryEvent(
                            id: id,
                            type: .tempBasal,
                            timestamp: timestamp,
                            amount: tempBasalRate as Decimal,
                            duration: Int(tempBasal.duration),
                            deliveredUnits: tempBasal.deliveredUnits as Decimal?,
                            insulinType: event.insulinType
                        )
                    } else {
                        return nil
                    }

                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }
}

extension BasePumpHistoryStorage {
    static let reconciledResumePrefix = "reconciled-resume:"

    static func isReconciledResume(_ row: PumpEventStored) -> Bool {
        row.type == PumpEvent.pumpResume.rawValue
            && (row.syncIdentifier?.hasPrefix(reconciledResumePrefix) == true)
    }

    static func reconciledResumeSyncIdentifier(for suspendRow: PumpEventStored, suspendDate: Date) -> String {
        let sourceKey = suspendRow.syncIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? suspendRow.id.flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(suspendDate.timeIntervalSinceReferenceDate)"
        return "\(reconciledResumePrefix)\(sourceKey)"
    }

    private static func latestAuthoritativeTransition(
        in context: NSManagedObjectContext,
        atOrBefore cutoff: Date
    ) throws -> PumpEventStored? {
        let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
        request.predicate = NSPredicate(
            format: "timestamp <= %@ AND type IN %@ AND (syncIdentifier == nil OR NOT (syncIdentifier BEGINSWITH %@))",
            cutoff as NSDate,
            [PumpEvent.pumpSuspend.rawValue, PumpEvent.pumpResume.rawValue],
            reconciledResumePrefix
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return try context.fetch(request).first { !$0.isDeleted && !isReconciledResume($0) }
    }

    private static func fetchDerivedResumes(
        in context: NSManagedObjectContext,
        since startDate: Date
    ) throws -> [PumpEventStored] {
        let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND type == %@ AND syncIdentifier BEGINSWITH %@",
            startDate as NSDate,
            PumpEvent.pumpResume.rawValue,
            reconciledResumePrefix
        )
        return try context.fetch(request).filter { !$0.isDeleted }
    }

    private static func owningSuspendTimestamps(
        for derivedResumes: [PumpEventStored],
        in context: NSManagedObjectContext
    ) throws -> [Date] {
        let sourceKeys = Array(Set(derivedResumes.compactMap { row -> String? in
            guard let syncId = row.syncIdentifier,
                  syncId.hasPrefix(reconciledResumePrefix)
            else { return nil }
            let key = String(syncId.dropFirst(reconciledResumePrefix.count))
            return key.isEmpty ? nil : key
        }))
        guard !sourceKeys.isEmpty else { return [] }

        let fallbackDates = sourceKeys
            .compactMap(Double.init)
            .filter(\.isFinite)
            .map(Date.init(timeIntervalSinceReferenceDate:))

        var matchPredicates: [NSPredicate] = [
            NSPredicate(format: "syncIdentifier IN %@", sourceKeys),
            NSPredicate(format: "id IN %@", sourceKeys)
        ]
        if !fallbackDates.isEmpty {
            matchPredicates.append(NSPredicate(format: "timestamp IN %@", fallbackDates))
        }

        let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(
                format: "type == %@ AND (syncIdentifier == nil OR NOT (syncIdentifier BEGINSWITH %@))",
                PumpEvent.pumpSuspend.rawValue,
                reconciledResumePrefix
            ),
            NSCompoundPredicate(orPredicateWithSubpredicates: matchPredicates)
        ])
        return try context.fetch(request)
            .filter { !$0.isDeleted }
            .compactMap(\.timestamp)
    }

    static func earliestPumpDeliveryDate(
        in context: NSManagedObjectContext,
        after suspendDate: Date,
        upTo upperBound: Date,
        inclusiveEnd: Bool
    ) throws -> Date? {
        guard upperBound > suspendDate else { return nil }
        let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
        let upperComparison = inclusiveEnd
            ? NSPredicate(format: "timestamp <= %@", upperBound as NSDate)
            : NSPredicate(format: "timestamp < %@", upperBound as NSDate)
        let afterPredicate = NSPredicate(format: "timestamp > %@", suspendDate as NSDate)
        let deliveryTypePredicate = NSPredicate(
            format: "(type == %@ AND bolus != nil AND bolus.isExternal == NO AND bolus.amount > 0) OR (type == %@ AND tempBasal != nil AND tempBasal.isScheduledBasal == NO AND (isMutable == YES OR tempBasal.duration > 0 OR tempBasal.deliveredUnits > 0))",
            PumpEvent.bolus.rawValue,
            PumpEvent.tempBasal.rawValue
        )
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            afterPredicate,
            upperComparison,
            deliveryTypePredicate
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return try context.fetch(request).first(where: { !$0.isDeleted })?.timestamp
    }

    static let nightscoutReuploadMarker = "reconciled-ns-reupload"
    static let replacedDerivedIdsPrefix = "reconciled-replaces:"
    private static let statusConfirmedNotePrefix = "reconciled-status-at:"

    private static func needsNightscoutReupload(_ row: PumpEventStored) -> Bool {
        !row.isUploadedToNS && (row.note?.contains(nightscoutReuploadMarker) == true)
    }

    static func replacedDerivedIds(of row: PumpEventStored) -> [String] {
        guard !row.isUploadedToNS, let note = row.note else { return [] }
        for segment in note.split(separator: ";") where segment.hasPrefix(replacedDerivedIdsPrefix) {
            return segment
                .dropFirst(replacedDerivedIdsPrefix.count)
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func statusConfirmedDates(of row: PumpEventStored) -> [Date] {
        guard let note = row.note else { return [] }
        for segment in note.split(separator: ";") where segment.hasPrefix(statusConfirmedNotePrefix) {
            return segment
                .dropFirst(statusConfirmedNotePrefix.count)
                .split(separator: ",")
                .compactMap { Double($0) }
                .filter(\.isFinite)
                .map { Date(timeIntervalSinceReferenceDate: $0) }
                .sorted()
        }
        return []
    }

    private static func deduplicatedDates(_ dates: [Date]) -> [Date] {
        var result: [Date] = []
        for date in dates.sorted() {
            if let last = result.last, abs(date.timeIntervalSince(last)) < 0.000001 {
                continue
            }
            result.append(date)
        }
        return result
    }

    /// Linear-time set difference on already-sorted date arrays (`lhs \ rhs` within 1 µs tolerance).
    private static func subtractSortedDates(_ lhs: [Date], removing rhs: [Date]) -> [Date] {
        guard !lhs.isEmpty, !rhs.isEmpty else { return lhs }
        var result: [Date] = []
        var rhsIndex = 0
        for candidate in lhs {
            while rhsIndex < rhs.count, rhs[rhsIndex].timeIntervalSince(candidate) <= -0.000001 {
                rhsIndex += 1
            }
            if rhsIndex < rhs.count, abs(rhs[rhsIndex].timeIntervalSince(candidate)) < 0.000001 {
                continue
            }
            result.append(candidate)
        }
        return result
    }

    private static func encodeReconciledNote(
        statusDates: [Date],
        needsNightscoutReupload: Bool,
        replacedIds: [String] = []
    ) -> String? {
        var segments: [String] = []
        if needsNightscoutReupload {
            segments.append(nightscoutReuploadMarker)
        } else if !replacedIds.isEmpty {
            let uniqueIds = Array(Set(replacedIds)).sorted()
            segments.append(replacedDerivedIdsPrefix + uniqueIds.joined(separator: ","))
        }
        let unique = deduplicatedDates(statusDates)
        if !unique.isEmpty {
            segments.append(
                statusConfirmedNotePrefix + unique.map { "\($0.timeIntervalSinceReferenceDate)" }.joined(separator: ",")
            )
        }
        return segments.isEmpty ? nil : segments.joined(separator: ";")
    }

    static func markNightscoutReupload(on row: PumpEventStored) {
        let encoded = encodeReconciledNote(
            statusDates: statusConfirmedDates(of: row),
            needsNightscoutReupload: true
        )
        if row.note != encoded {
            row.note = encoded
        }
    }

    private static func recordReplacedDerivedIds(_ derivedIds: [String], on row: PumpEventStored) {
        let nonEmpty = derivedIds.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty, !row.isUploadedToNS else { return }
        let encoded = encodeReconciledNote(
            statusDates: statusConfirmedDates(of: row),
            needsNightscoutReupload: needsNightscoutReupload(row),
            replacedIds: replacedDerivedIds(of: row) + nonEmpty
        )
        if row.note != encoded {
            row.note = encoded
        }
    }

    private static func deleteDerivedResume(
        _ derived: PumpEventStored,
        in context: NSManagedObjectContext,
        purgedUploadedIds: inout [String]
    ) {
        if derived.isUploadedToNS, let id = derived.id {
            purgedUploadedIds.append(id)
        }
        context.delete(derived)
    }

    @discardableResult
    private static func reanchorDerivedResume(
        _ derived: PumpEventStored,
        to newTimestamp: Date,
        purgedUploadedIds: inout [String]
    ) -> Bool {
        guard derived.timestamp != newTimestamp else { return false }
        derived.timestamp = newTimestamp
        guard derived.isUploadedToNS else { return false }
        if let oldId = derived.id {
            purgedUploadedIds.append(oldId)
        }
        // Rotate the treatment id so the detached DELETE for the old timestamp cannot
        // race against and delete the re-uploaded note at the corrected timestamp.
        derived.id = UUID().uuidString
        derived.isUploadedToNS = false
        return true
    }

    private static func upsertDerivedResume(
        existing: PumpEventStored?,
        syncIdentifier: String,
        at resumeDate: Date,
        statusConfirmedDates confirmedDates: [Date],
        in context: NSManagedObjectContext,
        purgedUploadedIds: inout [String]
    ) -> (row: PumpEventStored, mutatedTimeline: Bool) {
        let uniqueDates = deduplicatedDates(confirmedDates)
        if let existing {
            let hadPendingReupload = needsNightscoutReupload(existing)
            let timestampChanged = existing.timestamp != resumeDate
            var didPurgeUploaded = false
            if timestampChanged {
                didPurgeUploaded = reanchorDerivedResume(existing, to: resumeDate, purgedUploadedIds: &purgedUploadedIds)
            }
            let encodedNote = encodeReconciledNote(
                statusDates: uniqueDates,
                needsNightscoutReupload: hadPendingReupload || didPurgeUploaded,
                replacedIds: didPurgeUploaded ? [] : replacedDerivedIds(of: existing)
            )
            if existing.note != encodedNote {
                existing.note = encodedNote
            }
            return (existing, timestampChanged)
        }

        let encodedNote = encodeReconciledNote(
            statusDates: uniqueDates,
            needsNightscoutReupload: false
        )
        let resumeEvent = PumpEventStored(context: context)
        resumeEvent.id = UUID().uuidString
        resumeEvent.timestamp = resumeDate
        resumeEvent.type = PumpEvent.pumpResume.rawValue
        resumeEvent.syncIdentifier = syncIdentifier
        resumeEvent.note = encodedNote
        // Born final so `replacePendingEvents: true` batches from drivers that assert only
        // their own pending doses do not purge the reconciled resume on the next poll.
        resumeEvent.isMutable = false
        resumeEvent.isUploadedToNS = false
        resumeEvent.isUploadedToHealth = false
        resumeEvent.isUploadedToTidepool = false
        return (resumeEvent, true)
    }

    /// Reconciles authoritative `PumpSuspend` spans within `[lookbackStart, now]`, returning
    /// `true` when any derived `PumpResume` row was inserted, deleted, or had its timestamp changed.
    @discardableResult
    static func reconcileSuspensions(
        in context: NSManagedObjectContext,
        lookbackStart: Date,
        activeDeliverySince: Date?,
        lastVerifiedSyncDate: Date?,
        extraStatusDates: [Date],
        allowNewTrailingResume: Bool,
        now: Date,
        purgedUploadedIds: inout [String],
        unpersistedStatusDates: inout [Date]
    ) throws -> Bool {
        var effectiveLookbackStart = lookbackStart
        if let priorTransition = try latestAuthoritativeTransition(in: context, atOrBefore: effectiveLookbackStart),
           priorTransition.type == PumpEvent.pumpSuspend.rawValue,
           let priorSuspendDate = priorTransition.timestamp,
           priorSuspendDate < effectiveLookbackStart
        {
            effectiveLookbackStart = priorSuspendDate
        }

        var scopedDerivedResumes: [PumpEventStored] = []
        while true {
            scopedDerivedResumes = try fetchDerivedResumes(in: context, since: effectiveLookbackStart)
            let owningDates = try owningSuspendTimestamps(for: scopedDerivedResumes, in: context)
            if let earliestOwning = owningDates.min(), earliestOwning < effectiveLookbackStart {
                effectiveLookbackStart = earliestOwning
                if let priorTransition = try latestAuthoritativeTransition(in: context, atOrBefore: effectiveLookbackStart),
                   priorTransition.type == PumpEvent.pumpSuspend.rawValue,
                   let priorSuspendDate = priorTransition.timestamp,
                   priorSuspendDate < effectiveLookbackStart
                {
                    effectiveLookbackStart = priorSuspendDate
                }
            } else {
                break
            }
        }

        let derivedBySyncId = Dictionary(
            scopedDerivedResumes.compactMap { row in row.syncIdentifier.map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )

        let transitionRequest = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
        transitionRequest.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@ AND type IN %@",
            effectiveLookbackStart as NSDate,
            now as NSDate,
            [PumpEvent.pumpSuspend.rawValue, PumpEvent.pumpResume.rawValue]
        )
        transitionRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        let authoritativeRows = try context.fetch(transitionRequest).filter {
            !$0.isDeleted && !isReconciledResume($0)
        }

        let carrierRequest = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
        carrierRequest.predicate = NSPredicate(
            format: "note CONTAINS %@ AND (syncIdentifier == nil OR NOT (syncIdentifier BEGINSWITH %@))",
            statusConfirmedNotePrefix,
            reconciledResumePrefix
        )
        let confirmationCarriers = try context.fetch(carrierRequest).filter { !$0.isDeleted }
        let latestOverallTransition = try authoritativeRows.last
            ?? latestAuthoritativeTransition(in: context, atOrBefore: now)

        let freshTrailingDates: [Date] = allowNewTrailingResume
            ? [
                activeDeliverySince.map { min($0, now) },
                lastVerifiedSyncDate.map { min($0, now) }
            ].compactMap { $0 }
            : []

        let statusRetentionCutoff = min(
            effectiveLookbackStart,
            now.addingTimeInterval(-48.hours.timeInterval)
        )
        // Collect all previously recorded live-status confirmations within the retention horizon
        // (independent of carrier timestamp or whether a later hardware resume has already arrived).
        let recordedStatusDates = deduplicatedDates(
            (
                (scopedDerivedResumes + confirmationCarriers).flatMap(statusConfirmedDates(of:))
                    + extraStatusDates
                    + freshTrailingDates
            ).filter { $0 >= statusRetentionCutoff && $0 <= now }
        )

        var retainedDerivedRows: [PumpEventStored] = []
        var retainedDerivedIDs = Set<NSManagedObjectID>()
        var didMutateTimeline = false

        for index in authoritativeRows.indices {
            let row = authoritativeRows[index]
            guard row.type == PumpEvent.pumpSuspend.rawValue,
                  let suspendDate = row.timestamp
            else { continue }

            let resumeSyncId = reconciledResumeSyncIdentifier(for: row, suspendDate: suspendDate)
            let existingDerived = derivedBySyncId[resumeSyncId]
            let nextAuthoritative = (index + 1 < authoritativeRows.count) ? authoritativeRows[index + 1] : nil

            if let nextAuthoritative {
                guard let nextDate = nextAuthoritative.timestamp else { continue }
                if nextDate > suspendDate {
                    let earliestDelivery = try earliestPumpDeliveryDate(
                        in: context,
                        after: suspendDate,
                        upTo: nextDate,
                        inclusiveEnd: false
                    )
                    let matchingStatusDates = recordedStatusDates.filter {
                        $0 > suspendDate && $0 < nextDate
                    }
                    if let candidate = ([earliestDelivery] + matchingStatusDates.map { Optional($0) }).compactMap({ $0 }).min() {
                        let targetDate = max(candidate, suspendDate.addingTimeInterval(1))
                        if targetDate > suspendDate, targetDate < nextDate {
                            let upserted = upsertDerivedResume(
                                existing: existingDerived,
                                syncIdentifier: resumeSyncId,
                                at: targetDate,
                                statusConfirmedDates: matchingStatusDates,
                                in: context,
                                purgedUploadedIds: &purgedUploadedIds
                            )
                            retainedDerivedRows.append(upserted.row)
                            retainedDerivedIDs.insert(upserted.row.objectID)
                            didMutateTimeline = didMutateTimeline || upserted.mutatedTimeline
                        }
                    }
                }
                continue
            }

            // Trailing open `PumpSuspend` (`nextAuthoritative == nil`):
            guard (existingDerived != nil || allowNewTrailingResume),
                  now.timeIntervalSince(suspendDate) >= 1
            else { continue }

            let effectiveStatusDates = deduplicatedDates(
                recordedStatusDates.filter { $0 > suspendDate && $0 <= now }
            )

            let earliestDeliveryDate = try earliestPumpDeliveryDate(
                in: context,
                after: suspendDate,
                upTo: now,
                inclusiveEnd: true
            )
            // Require non-withdrawn post-suspend evidence; if supporting pending delivery was
            // purged or finalized to 0 U and no live status confirmation exists, retract.
            guard let rawResumeDate = ([earliestDeliveryDate] + effectiveStatusDates.map { Optional($0) }).compactMap({ $0 }).min() else {
                continue
            }
            let resumeDate = min(max(rawResumeDate, suspendDate.addingTimeInterval(1)), now)
            guard resumeDate > suspendDate else { continue }

            let upserted = upsertDerivedResume(
                existing: existingDerived,
                syncIdentifier: resumeSyncId,
                at: resumeDate,
                statusConfirmedDates: effectiveStatusDates,
                in: context,
                purgedUploadedIds: &purgedUploadedIds
            )
            retainedDerivedRows.append(upserted.row)
            retainedDerivedIDs.insert(upserted.row.objectID)
            didMutateTimeline = didMutateTimeline || upserted.mutatedTimeline
        }

        // Prune expired confirmation timestamps from authoritative carriers so `confirmationCarriers`
        // stays bounded to recent rows instead of accumulating 90 days of 5-minute sync dates.
        for carrier in confirmationCarriers where !carrier.isDeleted {
            let kept = statusConfirmedDates(of: carrier).filter { $0 >= statusRetentionCutoff && $0 <= now }
            let pruned = encodeReconciledNote(
                statusDates: kept,
                needsNightscoutReupload: needsNightscoutReupload(carrier),
                replacedIds: replacedDerivedIds(of: carrier)
            )
            if carrier.note != pruned {
                carrier.note = pruned
            }
        }

        // Preserve any confirmation timestamps not already carried by a retained derived row or
        // existing carrier row so subsequent history batches can still reconcile delayed gaps.
        let survivingCarriers = confirmationCarriers.filter { !$0.isDeleted }
        let persistedDates = deduplicatedDates(
            (retainedDerivedRows + survivingCarriers).flatMap(statusConfirmedDates(of:))
        )
        let missingDates = subtractSortedDates(recordedStatusDates, removing: persistedDates)
        if !missingDates.isEmpty {
            if let carrier = authoritativeRows.last ?? latestOverallTransition {
                let merged = deduplicatedDates(statusConfirmedDates(of: carrier) + missingDates)
                let encoded = encodeReconciledNote(
                    statusDates: merged,
                    needsNightscoutReupload: needsNightscoutReupload(carrier),
                    replacedIds: replacedDerivedIds(of: carrier)
                )
                if carrier.note != encoded {
                    carrier.note = encoded
                }
                unpersistedStatusDates = []
            } else {
                unpersistedStatusDates = missingDates
            }
        } else {
            unpersistedStatusDates = []
        }

        let survivingResumes = (authoritativeRows + retainedDerivedRows)
            .filter { !$0.isDeleted && $0.type == PumpEvent.pumpResume.rawValue }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        for derived in scopedDerivedResumes where !derived.isDeleted && !retainedDerivedIDs.contains(derived.objectID) {
            let owningDate = try owningSuspendTimestamps(for: [derived], in: context).min() ?? .distantPast
            if let replacement = survivingResumes.first(where: { ($0.timestamp ?? .distantPast) > owningDate }),
               !replacement.isUploadedToNS
            {
                if derived.isUploadedToNS || needsNightscoutReupload(derived) {
                    markNightscoutReupload(on: replacement)
                } else {
                    recordReplacedDerivedIds(
                        (derived.id.map { [$0] } ?? []) + replacedDerivedIds(of: derived),
                        on: replacement
                    )
                }
            }
            deleteDerivedResume(derived, in: context, purgedUploadedIds: &purgedUploadedIds)
            didMutateTimeline = true
        }
        return didMutateTimeline
    }

    /// Fallback upsert key for events without a dose identifier.
    struct TimestampAndType: Hashable {
        let timestamp: Date
        let type: String
        let isScheduledBasal: Bool
    }

    struct StoredCandidate {
        let event: NewPumpEvent
        let storedType: PumpEvent
        let date: Date
        let syncIdentifier: String?
        let isScheduledBasal: Bool
    }

    /// Expands a `NewPumpEvent` into its stored row(s).
    ///
    /// LoopKit keeps `NewPumpEvent.type` and `NewPumpEvent.dose` orthogonal: drivers such as
    /// MinimedKit attach `DoseEntry(suspendDate:)` or `DoseEntry(resumeDate:)` to `.rewind`,
    /// `.prime`, `.alarm` and `.alarmClear` events because Medtronic pumps exit suspend upon
    /// priming or clearing a no-delivery alarm without logging a separate `Resume` opcode.
    static func storedCandidates(for event: NewPumpEvent) -> [StoredCandidate] {
        let baseSyncIdentifier = event.dose?.syncIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        let primaryType = event.type?.storedEventType
        var candidates: [StoredCandidate] = []

        if let primaryType {
            candidates.append(StoredCandidate(
                event: event,
                storedType: primaryType,
                date: event.date,
                syncIdentifier: baseSyncIdentifier,
                isScheduledBasal: event.type == .basal
            ))
        }

        if let dose = event.dose,
           dose.type == .suspend || dose.type == .resume,
           primaryType != .pumpSuspend,
           primaryType != .pumpResume
        {
            let deliveryType: PumpEvent = dose.type == .suspend ? .pumpSuspend : .pumpResume
            let derivedSyncIdentifier = baseSyncIdentifier.map { "\($0):\(deliveryType.rawValue)" }
            candidates.append(StoredCandidate(
                event: event,
                storedType: deliveryType,
                date: dose.startDate,
                syncIdentifier: derivedSyncIdentifier,
                isScheduledBasal: false
            ))
        }

        return candidates
    }
}

extension PumpEventType {
    /// Scheduled-basal reports become TBR rows tagged `isScheduledBasal`.
    var storedEventType: PumpEventStored.EventType? {
        switch self {
        case .alarm: return .pumpAlarm
        case .alarmClear: return nil
        case .basal: return .tempBasal
        case .bolus: return .bolus
        case .prime: return .prime
        case .resume: return .pumpResume
        case .rewind: return .rewind
        case .suspend: return .pumpSuspend
        case .tempBasal: return .tempBasal
        case .replaceComponent(componentType: .infusionSet),
             .replaceComponent(componentType: .pump): return .siteChange
        case .replaceComponent: return nil
        case .timeZoneSync: return nil
        @unknown default: return nil
        }
    }
}
