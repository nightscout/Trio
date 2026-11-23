import CoreData
import Foundation
import LoopKit
import SwiftDate

extension BasePumpHistoryStorage {
    static let reconciledResumePrefix = "derived_resume_"

    struct StoredCandidate {
        let event: NewPumpEvent
        let storedType: PumpEvent
        let date: Date
        let syncIdentifier: String?
        let isScheduledBasal: Bool
    }

    /// Expands a `NewPumpEvent` into its stored row(s), matching LoopKit `DoseStore.addPumpEvents`
    /// (`LoopKit/InsulinKit/DoseStore.swift:680`), where `event.dose` is persisted orthogonally to
    /// `event.type`. Drivers such as `MinimedKit` (`MinimedKit/PumpManager/DoseStore.swift:110-140`)
    /// attach `DoseEntry(suspendDate:)` or `DoseEntry(resumeDate:)` to `.rewind`, `.prime`, `.alarm`
    /// and `.alarmClear` events because Medtronic pumps exit suspend upon priming or clearing a
    /// no-delivery alarm without logging a separate `Resume` opcode.
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

    static func isReconciledResume(_ row: PumpEventStored) -> Bool {
        row.type == PumpEvent.pumpResume.rawValue
            && (row.syncIdentifier?.hasPrefix(reconciledResumePrefix) == true)
    }

    private static func reconciledResumeSyncIdentifier(for suspendRow: PumpEventStored, suspendDate: Date) -> String {
        let sourceKey = suspendRow.syncIdentifier ?? suspendRow.id ?? "\(suspendDate.timeIntervalSinceReferenceDate)"
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
        request.fetchLimit = 4
        return try context.fetch(request).first { !$0.isDeleted }
    }

    private static func fetchDerivedResumes(
        in context: NSManagedObjectContext,
        since cutoff: Date
    ) throws -> [PumpEventStored] {
        let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND type == %@ AND syncIdentifier BEGINSWITH %@",
            cutoff as NSDate,
            PumpEvent.pumpResume.rawValue,
            reconciledResumePrefix
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return try context.fetch(request).filter { !$0.isDeleted }
    }

    private static func owningSuspendTimestamps(
        for derivedResumes: [PumpEventStored],
        in context: NSManagedObjectContext
    ) throws -> [Date] {
        let sourceKeys = derivedResumes.compactMap { row -> String? in
            guard let syncId = row.syncIdentifier, syncId.hasPrefix(reconciledResumePrefix) else { return nil }
            let key = String(syncId.dropFirst(reconciledResumePrefix.count))
            return key.isEmpty ? nil : key
        }
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

    private static func earliestPumpDeliveryDate(
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

    private static func upsertDerivedResume(
        existing: PumpEventStored?,
        syncIdentifier: String,
        at resumeDate: Date,
        in context: NSManagedObjectContext,
        purgedUploadedIds: inout [String]
    ) -> PumpEventStored {
        if let existing {
            if existing.timestamp != resumeDate {
                existing.timestamp = resumeDate
                if existing.isUploadedToNS {
                    if let oldId = existing.id {
                        purgedUploadedIds.append(oldId)
                    }
                    existing.id = UUID().uuidString
                    existing.isUploadedToNS = false
                }
            }
            return existing
        }

        let resumeEvent = PumpEventStored(context: context)
        resumeEvent.id = UUID().uuidString
        resumeEvent.timestamp = resumeDate
        resumeEvent.type = PumpEvent.pumpResume.rawValue
        resumeEvent.syncIdentifier = syncIdentifier
        resumeEvent.isMutable = false
        resumeEvent.isUploadedToNS = false
        resumeEvent.isUploadedToHealth = false
        resumeEvent.isUploadedToTidepool = false
        return resumeEvent
    }

    /// Ports LoopKit's missing-resume reconciliation (`LoopKit/InsulinKit/InsulinMath.swift:208-214`:
    /// *"Handle missing resume. Basal following suspend, with no resume"*) to Trio's `PumpEventStored`
    /// timeline: when pump delivery (`tempBasal` or non-external `bolus > 0`) occurs after an unclosed
    /// `PumpSuspend` (e.g. cancelled fixed prime on Medtronic), closes the suspension at the earliest
    /// post-suspend delivery timestamp and retracts if provisional delivery is later withdrawn or `0 U`.
    static func reconcileSuspensions(
        in context: NSManagedObjectContext,
        lookbackStart: Date,
        now: Date,
        purgedUploadedIds: inout [String]
    ) throws {
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

        var retainedDerivedIDs = Set<NSManagedObjectID>()

        for index in authoritativeRows.indices {
            let row = authoritativeRows[index]
            guard row.type == PumpEvent.pumpSuspend.rawValue,
                  let suspendDate = row.timestamp
            else { continue }

            let resumeSyncId = reconciledResumeSyncIdentifier(for: row, suspendDate: suspendDate)
            let existingDerived = derivedBySyncId[resumeSyncId]
            let nextAuthoritative = (index + 1 < authoritativeRows.count) ? authoritativeRows[index + 1] : nil

            if let nextAuthoritative {
                guard let nextDate = nextAuthoritative.timestamp, nextDate > suspendDate,
                      let deliveryDate = try earliestPumpDeliveryDate(
                          in: context,
                          after: suspendDate,
                          upTo: nextDate,
                          inclusiveEnd: false
                      )
                else { continue }
                let targetDate = max(deliveryDate, suspendDate.addingTimeInterval(1))
                guard targetDate < nextDate else { continue }
                let upserted = upsertDerivedResume(
                    existing: existingDerived,
                    syncIdentifier: resumeSyncId,
                    at: targetDate,
                    in: context,
                    purgedUploadedIds: &purgedUploadedIds
                )
                retainedDerivedIDs.insert(upserted.objectID)
                continue
            }

            guard now.timeIntervalSince(suspendDate) >= 1,
                  let deliveryDate = try earliestPumpDeliveryDate(
                      in: context,
                      after: suspendDate,
                      upTo: now,
                      inclusiveEnd: true
                  )
            else { continue }
            let resumeDate = min(max(deliveryDate, suspendDate.addingTimeInterval(1)), now)
            guard resumeDate > suspendDate else { continue }
            let upserted = upsertDerivedResume(
                existing: existingDerived,
                syncIdentifier: resumeSyncId,
                at: resumeDate,
                in: context,
                purgedUploadedIds: &purgedUploadedIds
            )
            retainedDerivedIDs.insert(upserted.objectID)
        }

        for derived in scopedDerivedResumes where !derived.isDeleted && !retainedDerivedIDs.contains(derived.objectID) {
            if derived.isUploadedToNS, let id = derived.id {
                purgedUploadedIds.append(id)
            }
            context.delete(derived)
        }
    }
}
