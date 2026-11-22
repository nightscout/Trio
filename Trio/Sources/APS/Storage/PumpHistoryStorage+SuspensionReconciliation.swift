import CoreData
import Foundation
import LoopKit
import SwiftDate

extension BasePumpHistoryStorage {
    static let reconciledResumePrefix = "derived_resume_"
    private static let statusConfirmedNotePrefix = "reconciled-status-at:"

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

    static func isReconciledResume(_ row: PumpEventStored) -> Bool {
        row.type == PumpEvent.pumpResume.rawValue
            && (row.syncIdentifier?.hasPrefix(reconciledResumePrefix) == true)
    }

    static func reconciledResumeSyncIdentifier(for suspendRow: PumpEventStored, suspendDate: Date) -> String {
        let sourceKey = suspendRow.syncIdentifier ?? suspendRow.id ?? "\(suspendDate.timeIntervalSinceReferenceDate)"
        return "\(reconciledResumePrefix)\(sourceKey)"
    }

    static func statusConfirmedDates(of row: PumpEventStored) -> [Date] {
        guard let note = row.note, note.hasPrefix(statusConfirmedNotePrefix) else { return [] }
        return note
            .dropFirst(statusConfirmedNotePrefix.count)
            .split(separator: ",")
            .compactMap { Double($0) }
            .filter(\.isFinite)
            .map(Date.init(timeIntervalSinceReferenceDate:))
            .sorted()
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

    private static func encodeStatusNote(_ dates: [Date]) -> String? {
        let unique = deduplicatedDates(dates)
        guard !unique.isEmpty else { return nil }
        return statusConfirmedNotePrefix + unique.map { "\($0.timeIntervalSinceReferenceDate)" }.joined(separator: ",")
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

    private static func upsertDerivedResume(
        existing: PumpEventStored?,
        syncIdentifier: String,
        at resumeDate: Date,
        statusConfirmedDates confirmedDates: [Date],
        in context: NSManagedObjectContext,
        purgedUploadedIds: inout [String]
    ) -> (row: PumpEventStored, mutatedTimeline: Bool) {
        let encodedNote = encodeStatusNote(confirmedDates)
        if let existing {
            let timestampChanged = existing.timestamp != resumeDate
            if timestampChanged {
                existing.timestamp = resumeDate
                if existing.isUploadedToNS {
                    if let oldId = existing.id {
                        purgedUploadedIds.append(oldId)
                    }
                    existing.id = UUID().uuidString
                    existing.isUploadedToNS = false
                }
            }
            if existing.note != encodedNote {
                existing.note = encodedNote
            }
            return (existing, timestampChanged)
        }

        let resumeEvent = PumpEventStored(context: context)
        resumeEvent.id = UUID().uuidString
        resumeEvent.timestamp = resumeDate
        resumeEvent.type = PumpEvent.pumpResume.rawValue
        resumeEvent.syncIdentifier = syncIdentifier
        resumeEvent.note = encodedNote
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
        purgedUploadedIds: inout [String]
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

        let freshTrailingDates: [Date] = allowNewTrailingResume
            ? [
                activeDeliverySince.map { min($0, now) },
                lastVerifiedSyncDate.map { min($0, now) }
            ].compactMap { $0 }
            : []

        let recordedStatusDates = deduplicatedDates(
            scopedDerivedResumes.flatMap(statusConfirmedDates(of:))
                + extraStatusDates
                + freshTrailingDates
        )

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
                guard let nextDate = nextAuthoritative.timestamp, nextDate > suspendDate else { continue }
                let earliestDelivery = try earliestPumpDeliveryDate(
                    in: context,
                    after: suspendDate,
                    upTo: nextDate,
                    inclusiveEnd: false
                )
                let matchingStatusDates = recordedStatusDates.filter { $0 > suspendDate && $0 < nextDate }
                if let candidate = ([earliestDelivery] + matchingStatusDates.map(Optional.init)).compactMap({ $0 }).min() {
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
                        retainedDerivedIDs.insert(upserted.row.objectID)
                        didMutateTimeline = didMutateTimeline || upserted.mutatedTimeline
                    }
                }
                continue
            }

            guard now.timeIntervalSince(suspendDate) >= 1 else { continue }

            let effectiveStatusDates = recordedStatusDates.filter { $0 > suspendDate && $0 <= now }
            let earliestDeliveryDate = try earliestPumpDeliveryDate(
                in: context,
                after: suspendDate,
                upTo: now,
                inclusiveEnd: true
            )
            guard let rawResumeDate = ([earliestDeliveryDate] + effectiveStatusDates.map(Optional.init)).compactMap({ $0 }).min() else {
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
            retainedDerivedIDs.insert(upserted.row.objectID)
            didMutateTimeline = didMutateTimeline || upserted.mutatedTimeline
        }

        for derived in scopedDerivedResumes where !derived.isDeleted && !retainedDerivedIDs.contains(derived.objectID) {
            if derived.isUploadedToNS, let id = derived.id {
                purgedUploadedIds.append(id)
            }
            context.delete(derived)
            didMutateTimeline = true
        }
        return didMutateTimeline
    }
}
