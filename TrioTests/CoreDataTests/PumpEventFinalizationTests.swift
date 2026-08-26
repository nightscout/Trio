import CoreData
import Foundation
import Swinject
import Testing

@testable import LoopKit
@testable import Trio

/// Ports LoopKit DoseStore finalization semantics to Trio's storage:
/// mutable rows update in place, finalized rows freeze, a complete pending
/// report purges unasserted mutable rows (replacePendingEvents).
@Suite("Pump Event Finalization Tests", .serialized) struct PumpEventFinalizationTests: Injectable {
    @Injected() var storage: PumpHistoryStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!
    typealias PumpEvent = PumpEventStored.EventType

    init() async throws {
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()

        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext)
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    // MARK: - Event factories

    // NewPumpEvent overwrites dose.syncIdentifier with raw.hexadecimalString, so raw carries identity
    private func storedIdentifier(_ identifier: String) -> String {
        Data(identifier.utf8).hexadecimalString
    }

    private func bolusEvent(
        date: Date,
        units: Double,
        deliveredUnits: Double? = nil,
        syncIdentifier: String?,
        isMutable: Bool,
        automatic: Bool = true
    ) -> LoopKit.NewPumpEvent {
        LoopKit.NewPumpEvent(
            date: date,
            dose: LoopKit.DoseEntry(
                type: .bolus,
                startDate: date,
                value: units,
                unit: .units,
                deliveredUnits: deliveredUnits,
                description: nil,
                syncIdentifier: syncIdentifier,
                scheduledBasalRate: nil,
                insulinType: .lyumjev,
                automatic: automatic,
                manuallyEntered: false,
                isMutable: isMutable
            ),
            raw: Data((syncIdentifier ?? UUID().uuidString).utf8),
            title: "Test Bolus",
            type: .bolus
        )
    }

    private func tempBasalEvent(
        start: Date,
        end: Date,
        rate: Double,
        deliveredUnits: Double? = nil,
        syncIdentifier: String?,
        isMutable: Bool
    ) -> LoopKit.NewPumpEvent {
        LoopKit.NewPumpEvent(
            date: start,
            dose: LoopKit.DoseEntry(
                type: .tempBasal,
                startDate: start,
                endDate: end,
                value: rate,
                unit: .unitsPerHour,
                deliveredUnits: deliveredUnits,
                description: nil,
                syncIdentifier: syncIdentifier,
                scheduledBasalRate: nil,
                insulinType: .lyumjev,
                automatic: true,
                manuallyEntered: false,
                isMutable: isMutable
            ),
            raw: Data((syncIdentifier ?? UUID().uuidString).utf8),
            title: "Test Temp Basal",
            type: .tempBasal
        )
    }

    private func fetchAllEvents() async throws -> [PumpEventStored] {
        try await testContext.perform {
            try testContext.fetch(PumpEventStored.fetchRequest())
        }
    }

    // MARK: - Mutable lifecycle

    @Test("Mutable temp basal is updated in place, not duplicated") func testMutableTempBasalUpdatedInPlace() async throws {
        let start = Date().addingTimeInterval(-20.minutes.timeInterval)

        try await storage.storePumpEvents(
            [tempBasalEvent(
                start: start,
                end: start.addingTimeInterval(30.minutes.timeInterval),
                rate: 1.375,
                syncIdentifier: "tbr-1",
                isMutable: true
            )],
            replacePendingEvents: false
        )
        // pump re-asserts the same running temp with revised rate and end
        try await storage.storePumpEvents(
            [tempBasalEvent(
                start: start,
                end: start.addingTimeInterval(20.minutes.timeInterval),
                rate: 0.875,
                syncIdentifier: "tbr-1",
                isMutable: true
            )],
            replacePendingEvents: false
        )

        let events = try await fetchAllEvents()
        #expect(events.count == 1, "Re-asserted mutable event must not duplicate")
        let row = events.first
        #expect(row?.isMutable == true, "Row should still be mutable")
        #expect(row?.tempBasal?.rate as? Decimal == 0.875, "Rate should be updated")
        #expect(row?.tempBasal?.duration == 20, "Duration should be updated")
    }

    @Test("Interrupted bolus finalizes with delivered units on the same row") func testInterruptedBolusFinalized() async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)

        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 5.0, syncIdentifier: "bolus-1", isMutable: true)],
            replacePendingEvents: false
        )
        // interruption: pump reports actual delivery, dose finalized
        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 5.0, deliveredUnits: 2.4, syncIdentifier: "bolus-1", isMutable: false)],
            replacePendingEvents: false
        )

        let events = try await fetchAllEvents()
        #expect(events.count == 1, "Finalization must reuse the mutable row")
        let row = events.first
        #expect(row?.isMutable == false, "Row should be finalized")
        // Double→Decimal rounding leaves binary noise; compare with tolerance
        let amount = row?.bolus?.amount?.doubleValue ?? 0
        #expect(abs(amount - 2.4) < 0.0001, "Amount should be the delivered units, not programmed units")
        let programmed = row?.bolus?.programmedAmount?.doubleValue ?? 0
        #expect(abs(programmed - 5.0) < 0.0001, "Programmed amount must survive finalization")
    }

    @Test("Finalizing an uploaded bolus with changed delivery resets the NS upload flag") func testChangedFinalizationResetsNSFlag(
    ) async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)

        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 5.0, syncIdentifier: "bolus-ns", isMutable: true)],
            replacePendingEvents: false
        )
        // mutable row was uploaded to NS
        try await testContext.perform {
            let rows = try testContext.fetch(PumpEventStored.fetchRequest())
            rows.forEach { $0.isUploadedToNS = true }
            try testContext.save()
        }
        // cancelled: delivered less than programmed
        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 5.0, deliveredUnits: 2.4, syncIdentifier: "bolus-ns", isMutable: false)],
            replacePendingEvents: false
        )

        let events = try await fetchAllEvents()
        #expect(events.first?.isUploadedToNS == false, "Changed values must re-upload so NS upserts the document")
    }

    @Test("Finalizing an uploaded bolus without changes keeps the NS upload flag") func testUnchangedFinalizationKeepsNSFlag(
    ) async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)

        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 1.5, syncIdentifier: "bolus-ns2", isMutable: true)],
            replacePendingEvents: false
        )
        try await testContext.perform {
            let rows = try testContext.fetch(PumpEventStored.fetchRequest())
            rows.forEach { $0.isUploadedToNS = true }
            try testContext.save()
        }
        // delivered exactly as programmed
        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 1.5, deliveredUnits: 1.5, syncIdentifier: "bolus-ns2", isMutable: false)],
            replacePendingEvents: false
        )

        let events = try await fetchAllEvents()
        #expect(events.first?.isUploadedToNS == true, "Unchanged finalization must not re-upload")
    }

    @Test("Insulin model snapshot is stored per event") func testInsulinSnapshotStored() async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)

        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 1.0, deliveredUnits: 1.0, syncIdentifier: "bolus-snap", isMutable: false)],
            replacePendingEvents: false
        )

        let settings = resolver.resolve(SettingsManager.self)!
        let events = try await fetchAllEvents()
        let row = events.first
        #expect(row?.insulinType == LoopKit.InsulinType.lyumjev.identifier, "Pump-reported insulin type must be stored")
        #expect(row?.actionDuration as? Decimal == settings.pumpSettings.insulinActionCurve, "DIA snapshot must match settings")
        #expect(row?.peakTime as? Decimal == 75, "Default rapid-acting peak is 75 min")
    }

    /// `IobCalculation` can't import LoopKit (the algorithm package compiles it
    /// without it), so its default peaks are literals. Pin them to the presets
    /// they mirror; this fails if LoopKit ever changes them.
    @Test("Default peaks match LoopKit's exponential presets") func testDefaultPeaksMatchLoopKit() throws {
        let rapidActing = IobCalculation.lookupPeak(curve: .rapidActing, useCustomPeakTime: false, insulinPeakTime: 0)
        let ultraRapid = IobCalculation.lookupPeak(curve: .ultraRapid, useCustomPeakTime: false, insulinPeakTime: 0)

        #expect(rapidActing == ExponentialInsulinModelPreset.rapidActingAdult.peakActivity / 60)
        #expect(ultraRapid == ExponentialInsulinModelPreset.fiasp.peakActivity / 60)
    }

    // MARK: - Remote payloads

    @Test("Health and Tidepool payloads carry the dose's own insulin data") func testUploadPayloadsCarryDoseData() async throws {
        let date = Date().addingTimeInterval(-30.minutes.timeInterval)
        try await storage.storePumpEvents(
            [
                bolusEvent(date: date, units: 5.0, deliveredUnits: 2.4, syncIdentifier: "bolus-payload", isMutable: false),
                tempBasalEvent(
                    start: date,
                    end: date.addingTimeInterval(30.minutes.timeInterval),
                    rate: 1.0,
                    deliveredUnits: 0.35,
                    syncIdentifier: "tbr-payload",
                    isMutable: false
                )
            ],
            replacePendingEvents: false
        )

        let health = try await storage.getPumpHistoryNotYetUploadedToHealth()
        let tidepool = try await storage.getPumpHistoryNotYetUploadedToTidepool()

        for payload in [health, tidepool] {
            let bolus = payload.first { $0.type == .bolus }
            let tempBasal = payload.first { $0.type == .tempBasal }
            #expect(bolus?.insulinType == LoopKit.InsulinType.lyumjev.identifier, "Dose insulin type must reach the uploader")
            #expect(tempBasal?.deliveredUnits == 0.35, "Pump-reported delivery must reach the uploader")
        }
        // programmed vs delivered is a Tidepool-only distinction today;
        // Double->Decimal rounding leaves binary noise, so compare with tolerance
        let tidepoolBolus = tidepool.first { $0.type == .bolus }
        #expect(abs((tidepoolBolus?.amount ?? 0) - 2.4) < 0.0001, "Delivered units")
        #expect(abs((tidepoolBolus?.programmedAmount ?? 0) - 5.0) < 0.0001, "Programmed units")
    }

    @Test("External doses expose no insulin type to uploaders") func testExternalDoseHasNoInsulinType() async throws {
        await storage.storeExternalInsulinEvent(amount: 2.0, timestamp: Date().addingTimeInterval(-10.minutes.timeInterval))

        let tidepool = try await storage.getPumpHistoryNotYetUploadedToTidepool()
        let health = try await storage.getPumpHistoryNotYetUploadedToHealth()
        #expect(tidepool.first?.insulinType == nil, "External insulin is not the pump's insulin")
        #expect(tidepool.first?.isExternal == true)
        #expect(health.first?.isExternal == true, "Health needs this to suppress the pump-type fallback")
    }

    @Test("Finalized rows are frozen against later reports") func testFinalizedRowIsFrozen() async throws {
        let date = Date().addingTimeInterval(-10.minutes.timeInterval)

        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 1.0, deliveredUnits: 1.0, syncIdentifier: "bolus-2", isMutable: false)],
            replacePendingEvents: false
        )
        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 3.0, deliveredUnits: 3.0, syncIdentifier: "bolus-2", isMutable: false)],
            replacePendingEvents: false
        )

        let events = try await fetchAllEvents()
        #expect(events.count == 1, "Same syncIdentifier must not duplicate")
        #expect(events.first?.bolus?.amount as? Decimal == 1.0, "Finalized amount must not change")
    }

    // MARK: - replacePendingEvents purge (LoopKit contract)

    @Test("Unasserted mutable events are purged when pending events are replaced") func testReplacePendingEventsPurgesUnasserted(
    ) async throws {
        let now = Date()

        // finalized row must survive any purge
        try await storage.storePumpEvents(
            [bolusEvent(
                date: now.addingTimeInterval(-30.minutes.timeInterval),
                units: 0.5,
                deliveredUnits: 0.5,
                syncIdentifier: "bolus-final",
                isMutable: false
            )],
            replacePendingEvents: false
        )
        // mutable temp basal the pump later stops reporting (missed finalization)
        try await storage.storePumpEvents(
            [tempBasalEvent(
                start: now.addingTimeInterval(-15.minutes.timeInterval),
                end: now.addingTimeInterval(15.minutes.timeInterval),
                rate: 2.0,
                syncIdentifier: "tbr-orphan",
                isMutable: true
            )],
            replacePendingEvents: false
        )
        // next complete pending report no longer contains the orphan
        try await storage.storePumpEvents(
            [bolusEvent(date: now, units: 1.0, deliveredUnits: 1.0, syncIdentifier: "bolus-3", isMutable: false)],
            replacePendingEvents: true
        )

        let events = try await fetchAllEvents()
        let identifiers = events.compactMap(\.syncIdentifier)
        #expect(!identifiers.contains(storedIdentifier("tbr-orphan")), "Unasserted mutable event must be purged")
        #expect(identifiers.contains(storedIdentifier("bolus-final")), "Finalized rows must survive the purge")
        #expect(identifiers.contains(storedIdentifier("bolus-3")), "Newly reported event must be stored")
    }

    @Test("Purged uploaded events report their ids for remote deletion") func testPurgeReportsUploadedIds() async throws {
        let start = Date().addingTimeInterval(-15.minutes.timeInterval)

        try await storage.storePumpEvents(
            [tempBasalEvent(
                start: start,
                end: start.addingTimeInterval(30.minutes.timeInterval),
                rate: 2.0,
                syncIdentifier: "tbr-ghost",
                isMutable: true
            )],
            replacePendingEvents: false
        )
        // orphan was already uploaded to NS before the pump withdrew it
        try await testContext.perform {
            let rows = try testContext.fetch(PumpEventStored.fetchRequest())
            rows.forEach { $0.isUploadedToNS = true }
            try testContext.save()
        }

        let purged = try await storage.storePumpEvents(
            [bolusEvent(date: Date(), units: 1.0, deliveredUnits: 1.0, syncIdentifier: "bolus-x", isMutable: false)],
            replacePendingEvents: true
        )

        #expect(purged.count == 1, "The uploaded orphan must be reported for remote deletion")
        let events = try await fetchAllEvents()
        #expect(!events.compactMap(\.syncIdentifier).contains(storedIdentifier("tbr-ghost")), "Orphan must be purged locally")
    }

    @Test("Asserted mutable events survive pending replacement") func testReplacePendingEventsKeepsAsserted() async throws {
        let start = Date().addingTimeInterval(-10.minutes.timeInterval)
        let event = tempBasalEvent(
            start: start,
            end: start.addingTimeInterval(30.minutes.timeInterval),
            rate: 1.2,
            syncIdentifier: "tbr-live",
            isMutable: true
        )

        try await storage.storePumpEvents([event], replacePendingEvents: false)
        try await storage.storePumpEvents([event], replacePendingEvents: true)

        let events = try await fetchAllEvents()
        #expect(events.count == 1, "Re-asserted event must survive as a single row")
        #expect(events.first?.syncIdentifier == storedIdentifier("tbr-live"))
        #expect(events.first?.isMutable == true)
    }

    // MARK: - Identity edge cases

    @Test("Same-timestamp bolus and temp basal don't shadow each other") func testSameTimestampBolusAndTempBasal() async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)

        // no syncIdentifiers: storage must fall back to timestamp+type, not timestamp alone
        try await storage.storePumpEvents(
            [
                bolusEvent(date: date, units: 0.5, deliveredUnits: 0.5, syncIdentifier: nil, isMutable: false),
                tempBasalEvent(
                    start: date,
                    end: date.addingTimeInterval(30.minutes.timeInterval),
                    rate: 1.5,
                    syncIdentifier: nil,
                    isMutable: false
                )
            ],
            replacePendingEvents: false
        )

        let events = try await fetchAllEvents()
        #expect(events.count == 2, "Both events must be stored")
        #expect(events.contains { $0.type == PumpEvent.bolus.rawValue })
        #expect(events.contains { $0.type == PumpEvent.tempBasal.rawValue })
    }

    @Test("Duplicate events within one batch are deduplicated") func testDuplicateEventsWithinBatch() async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)
        let event = bolusEvent(date: date, units: 0.5, deliveredUnits: 0.5, syncIdentifier: "bolus-dup", isMutable: false)

        try await storage.storePumpEvents([event, event], replacePendingEvents: false)

        let events = try await fetchAllEvents()
        #expect(events.count == 1, "Same event twice in one batch must yield one row")
    }

    @Test("Purging a pump event cascades to its dose child") func testPurgeCascadesToChild() async throws {
        let start = Date().addingTimeInterval(-10.minutes.timeInterval)

        try await storage.storePumpEvents(
            [tempBasalEvent(
                start: start,
                end: start.addingTimeInterval(30.minutes.timeInterval),
                rate: 1.0,
                syncIdentifier: "tbr-cascade",
                isMutable: true
            )],
            replacePendingEvents: false
        )
        try await storage.storePumpEvents(
            [bolusEvent(date: Date(), units: 0.5, deliveredUnits: 0.5, syncIdentifier: "bolus-y", isMutable: false)],
            replacePendingEvents: true
        )

        let orphanedChildren = try await testContext.perform {
            try testContext.fetch(TempBasalStored.fetchRequest() as NSFetchRequest<TempBasalStored>)
                .filter { $0.pumpEvent == nil }
        }
        #expect(orphanedChildren.isEmpty, "Purging the parent must delete the dose child, not orphan it")
    }

    @Test("Same sync identifier cannot exist twice, nil identifiers can") func testSyncIdentifierUniqueness() async throws {
        try await testContext.perform {
            for _ in 0 ..< 2 {
                let event = PumpEventStored(context: testContext)
                event.id = UUID().uuidString
                event.timestamp = Date()
                event.type = PumpEvent.bolus.rawValue
                event.syncIdentifier = "constraint-dup"
            }
            for _ in 0 ..< 2 {
                let event = PumpEventStored(context: testContext)
                event.id = UUID().uuidString
                event.timestamp = Date()
                event.type = PumpEvent.pumpSuspend.rawValue
                event.syncIdentifier = nil
            }
            testContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
            try testContext.save()
        }

        let events = try await fetchAllEvents()
        #expect(events.filter { $0.syncIdentifier == "constraint-dup" }.count == 1, "Constraint must dedupe by syncIdentifier")
        #expect(events.filter { $0.syncIdentifier == nil }.count == 2, "Nil identifiers must not be constrained")
    }

    @Test("External insulin is born finalized with a sync identifier") func testExternalInsulinBornFinal() async throws {
        await storage.storeExternalInsulinEvent(amount: 1.5, timestamp: Date().addingTimeInterval(-5.minutes.timeInterval))

        let events = try await fetchAllEvents()
        #expect(events.count == 1)
        let row = events.first
        #expect(row?.isMutable == false, "Trio-created records are their own source of truth")
        #expect(row?.syncIdentifier != nil, "External insulin needs a stable identity")
        #expect(row?.bolus?.isExternal == true)
        #expect(row?.bolus?.amount as? Decimal == 1.5)
        #expect(row?.bolus?.programmedAmount as? Decimal == 1.5)
        #expect(row?.insulinType == nil, "Insulin type is unknown for doses external to the pump")
        #expect(row?.actionDuration == nil, "External doses don't snapshot the pump insulin model")
        #expect(row?.peakTime == nil, "External doses don't snapshot the pump insulin model")
    }

    @Test("Suspends and resumes flow into pump history for TDD") func testSuspendResumeInPumpHistory() async throws {
        let date = Date().addingTimeInterval(-30.minutes.timeInterval)
        let suspend = LoopKit.NewPumpEvent(date: date, dose: nil, raw: Data("suspend-1".utf8), title: "Suspend", type: .suspend)
        let resume = LoopKit.NewPumpEvent(
            date: date.addingTimeInterval(10.minutes.timeInterval),
            dose: nil,
            raw: Data("resume-1".utf8),
            title: "Resume",
            type: .resume
        )
        try await storage.storePumpEvents([suspend, resume], replacePendingEvents: false)

        let history = try await storage.getPumpHistory()
        #expect(history.contains { $0.type == .pumpSuspend }, "Suspends feed the inference timeline")
        #expect(history.contains { $0.type == .pumpResume }, "Resumes feed the inference timeline")
    }

    // MARK: - Scheduled basal

    /// A driver's `.basal` report, with whatever end it claims: MinimedKit sends a 24 h
    /// placeholder it expects the caller to reconcile; DanaKit, MedtrumKit and TandemKit send a
    /// zero-length dose. OmnipodKit reports no `.basal` at all, so it has no shape to test here.
    private func scheduledBasalEvent(
        start: Date,
        rate: Double,
        claimedDuration: TimeInterval,
        syncIdentifier: String
    ) -> LoopKit.NewPumpEvent {
        LoopKit.NewPumpEvent(
            date: start,
            dose: LoopKit.DoseEntry(
                type: .basal,
                startDate: start,
                endDate: start.addingTimeInterval(claimedDuration),
                value: rate,
                unit: .unitsPerHour,
                deliveredUnits: nil,
                description: nil,
                syncIdentifier: syncIdentifier,
                scheduledBasalRate: nil,
                insulinType: .lyumjev,
                automatic: nil,
                manuallyEntered: false,
                isMutable: false
            ),
            raw: Data(syncIdentifier.utf8),
            title: "Scheduled Basal",
            type: .basal
        )
    }

    @Test("Scheduled basal is stored open-ended, whatever span the driver claims") func testScheduledBasalStoredOpenEnded() async throws {
        let start = Date().addingTimeInterval(-40.minutes.timeInterval)
        try await storage.storePumpEvents([
            // MinimedKit's 24 h placeholder, then the zero-length shape Dana, Medtrum and Tandem send
            scheduledBasalEvent(start: start, rate: 1.0, claimedDuration: 24 * 60 * 60, syncIdentifier: "sbr-minimed"),
            scheduledBasalEvent(start: start.addingTimeInterval(60), rate: 0.625, claimedDuration: 0, syncIdentifier: "sbr-dana"),
            scheduledBasalEvent(start: start.addingTimeInterval(120), rate: 0.8, claimedDuration: 0, syncIdentifier: "sbr-tandem")
        ], replacePendingEvents: false)

        let rows = try await fetchAllEvents().compactMap(\.tempBasal)
        let allTagged = rows.allSatisfy(\.isScheduledBasal)
        let allOpenEnded = rows.allSatisfy { $0.duration == 0 && $0.startDate == $0.endDate }
        #expect(rows.count == 3)
        #expect(allTagged)
        #expect(allOpenEnded, "A rate assertion carries no delivery span")
    }

    @Test(
        "Overlapping scheduled-basal rows accrue delivery once, not once per row"
    ) func testOverlappingScheduledBasalRowsDoNotMultiply() throws {
        let tddStorage = resolver.resolve(TDDStorage.self) as! BaseTDDStorage
        let now = Date()
        let start = now.addingTimeInterval(-60.minutes.timeInterval)
        // five 24 h rows a minute apart, as one basal-schedule edit produces on Medtronic
        let history = (0 ..< 5).map { index in
            PumpHistoryEvent(
                id: "sbr-\(index)",
                type: .tempBasal,
                timestamp: start.addingTimeInterval(Double(index) * 60),
                amount: 4.0,
                duration: 1440,
                isScheduledBasal: true
            )
        }

        let segments = ScheduledBasalInference.segments(
            events: BaseTDDStorage.timelineEvents(from: history),
            profile: [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)],
            now: now
        )
        let insulin = tddStorage.calculateScheduledBasalInsulin(
            segments,
            roundToSupportedBasalRate: { $0 }
        )

        // one hour of the 1 U/hr profile, however many rows asserted it and whatever rate they claim
        #expect(abs(Double(truncating: insulin as NSNumber) - 1.0) < 0.02)
    }

    @Test(
        "A scheduled-basal row claims no coverage, so the sweep still sizes the gap"
    ) func testScheduledBasalRowDoesNotMuteTheSweep() throws {
        let now = Date()
        let start = now.addingTimeInterval(-60.minutes.timeInterval)
        let history = [
            PumpHistoryEvent(
                id: "sbr",
                type: .tempBasal,
                timestamp: start,
                amount: 1.0,
                duration: 1440,
                isScheduledBasal: true
            )
        ]

        let events = BaseTDDStorage.timelineEvents(from: history)
        #expect(events.count == 1)
        #expect(events[0].end == events[0].start, "A 24 h placeholder must not mark a day covered")

        let segments = ScheduledBasalInference.segments(
            events: events,
            profile: [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)],
            now: now
        )
        #expect(!segments.isEmpty, "The hour since the row was reported is still swept")
    }

    @Test("A temp basal covering the span leaves nothing for the sweep to bill") func testTempBasalCoverageLeavesNoScheduledBasal() throws {
        let now = Date()
        let start = now.addingTimeInterval(-30.minutes.timeInterval)
        // Minimed reports a schedule boundary while a temp basal is running: the temp delivers
        let history = [
            PumpHistoryEvent(
                id: "sbr",
                type: .tempBasal,
                timestamp: start,
                amount: 1.0,
                duration: 1440,
                isScheduledBasal: true
            ),
            PumpHistoryEvent(
                id: "temp",
                type: .tempBasal,
                timestamp: start,
                amount: 0.5,
                duration: 30
            )
        ]

        let segments = ScheduledBasalInference.segments(
            events: BaseTDDStorage.timelineEvents(from: history),
            profile: [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)],
            now: now
        )

        // the temp basal covers the whole window, so scheduled basal is not billed on top of it
        let nothingSubstantial = segments.allSatisfy { $0.end.timeIntervalSince($0.start) < 60 }
        #expect(nothingSubstantial)
    }

    @Test("A gap no row describes is still inferred from the profile") func testUncoveredGapStillInferred() throws {
        let now = Date()
        let start = now.addingTimeInterval(-60.minutes.timeInterval)
        // a temp basal that expired half an hour ago, and nothing since: Omnipod's shape
        let history = [
            PumpHistoryEvent(
                id: "temp",
                type: .tempBasal,
                timestamp: start,
                amount: 0.5,
                duration: 30
            )
        ]

        let segments = ScheduledBasalInference.segments(
            events: BaseTDDStorage.timelineEvents(from: history),
            profile: [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)],
            now: now
        )

        #expect(!segments.isEmpty, "No row covers the last half hour, so the profile fills it")
    }

    // MARK: - Suspension pairing

    private func suspendEvent(_ date: Date) -> PumpHistoryEvent {
        PumpHistoryEvent(id: UUID().uuidString, type: .pumpSuspend, timestamp: date)
    }

    private func resumeEvent(_ date: Date) -> PumpHistoryEvent {
        PumpHistoryEvent(id: UUID().uuidString, type: .pumpResume, timestamp: date)
    }

    @Test("An unresumed suspension still pairs the earlier one") func testUnbalancedSuspensionPairing() throws {
        // pump history arrives newest-first: S1 R1 S2, still suspended
        let now = Date()
        let s1 = now.addingTimeInterval(-3.hours.timeInterval)
        let r1 = now.addingTimeInterval(-2.hours.timeInterval)
        let s2 = now.addingTimeInterval(-1.hours.timeInterval)

        let spans = BaseTDDStorage.suspensionSpans(
            suspends: [suspendEvent(s2), suspendEvent(s1)],
            resumes: [resumeEvent(r1)],
            now: now
        )

        #expect(spans.count == 2, "Both the closed and the open suspension must be represented")
        #expect(spans.first?.start == s1 && spans.first?.end == r1, "S1 must pair with R1, not be dropped")
        #expect(spans.last?.start == s2 && spans.last?.end == now, "An unresumed suspension runs to now")
    }

    @Test("Balanced suspensions pair chronologically") func testBalancedSuspensionPairing() throws {
        let now = Date()
        let s1 = now.addingTimeInterval(-4.hours.timeInterval)
        let r1 = now.addingTimeInterval(-3.hours.timeInterval)
        let s2 = now.addingTimeInterval(-2.hours.timeInterval)
        let r2 = now.addingTimeInterval(-1.hours.timeInterval)

        let spans = BaseTDDStorage.suspensionSpans(
            suspends: [suspendEvent(s2), suspendEvent(s1)],
            resumes: [resumeEvent(r2), resumeEvent(r1)],
            now: now
        )

        #expect(spans.count == 2)
        #expect(spans.first?.end == r1 && spans.last?.end == r2, "Each suspend pairs with the resume that ends it")
    }

    @Test("A leading resume without its suspend is ignored") func testLeadingResumeIgnored() throws {
        let now = Date()
        let r0 = now.addingTimeInterval(-3.hours.timeInterval)
        let s1 = now.addingTimeInterval(-2.hours.timeInterval)
        let r1 = now.addingTimeInterval(-1.hours.timeInterval)

        let spans = BaseTDDStorage.suspensionSpans(
            suspends: [suspendEvent(s1)],
            resumes: [resumeEvent(r1), resumeEvent(r0)],
            now: now
        )

        #expect(spans.count == 1)
        #expect(spans.first?.start == s1 && spans.first?.end == r1)
    }

    @Test("A suspension inside a running temp basal is not counted as delivered") func testSuspensionReducesTempBasalInsulin(
    ) throws {
        let tddStorage = resolver.resolve(TDDStorage.self) as! BaseTDDStorage
        let now = Date()
        let start = now.addingTimeInterval(-4.hours.timeInterval)
        // 1 U/hr for 4 h, suspended for the middle hour
        let tempBasal = PumpHistoryEvent(id: "tbr", type: .tempBasal, timestamp: start, amount: 1.0, duration: 240)
        let spans = BaseTDDStorage.suspensionSpans(
            suspends: [suspendEvent(start.addingTimeInterval(1.hours.timeInterval))],
            resumes: [resumeEvent(start.addingTimeInterval(2.hours.timeInterval))],
            now: now
        )

        let insulin = tddStorage.calculateTempBasalInsulin(
            [tempBasal],
            suspensions: spans,
            now: now,
            roundToSupportedBasalRate: { $0 }
        )

        #expect(abs(Double(truncating: insulin as NSNumber) - 3.0) < 0.001, "Only the three unsuspended hours deliver")
    }

    @Test("A running temp basal is clamped to now and to its successor") func testTempBasalClampedToNowAndSuccessor() throws {
        let tddStorage = resolver.resolve(TDDStorage.self) as! BaseTDDStorage
        let now = Date()
        let first = now.addingTimeInterval(-2.hours.timeInterval)
        // 2 U/hr scheduled for 2 h but replaced after 1 h, then 1 U/hr still running with 1 h elapsed
        let superseded = PumpHistoryEvent(id: "tbr1", type: .tempBasal, timestamp: first, amount: 2.0, duration: 120)
        let running = PumpHistoryEvent(
            id: "tbr2",
            type: .tempBasal,
            timestamp: now.addingTimeInterval(-1.hours.timeInterval),
            amount: 1.0,
            duration: 120
        )

        let insulin = tddStorage.calculateTempBasalInsulin(
            [superseded, running],
            suspensions: [],
            now: now,
            roundToSupportedBasalRate: { $0 }
        )

        #expect(abs(Double(truncating: insulin as NSNumber) - 3.0) < 0.001, "2 U for the first hour, 1 U so far for the second")
    }

    // MARK: - NS upload race (values changed while a POST was in flight)

    private func nsTreatment(insulin: Decimal?, rate: Decimal?, duration: Int?, eventType: PumpEvent) -> NightscoutTreatment {
        NightscoutTreatment(
            duration: duration,
            rawDuration: nil,
            rawRate: nil,
            absolute: rate,
            rate: rate,
            eventType: eventType,
            createdAt: Date(),
            enteredBy: NightscoutTreatment.local,
            bolus: nil,
            insulin: insulin,
            notes: nil,
            carbs: nil,
            fat: nil,
            protein: nil,
            targetTop: nil,
            targetBottom: nil,
            id: "race-row"
        )
    }

    @Test("Upload completion only stamps rows that still match what was sent") func testUploadStampVerifiesValues() async throws {
        try await testContext.perform {
            let event = PumpEventStored(context: testContext)
            event.id = "race-row"
            event.timestamp = Date()
            event.type = PumpEvent.bolus.rawValue
            let bolus = BolusStored(context: testContext)
            bolus.amount = 2.4 as NSDecimalNumber
            bolus.pumpEvent = event
            try testContext.save()

            // finalized to 2.4 U while the 5 U POST was in flight
            #expect(!BaseNightscoutManager.uploadStillCurrent(event, self.nsTreatment(
                insulin: 5.0,
                rate: nil,
                duration: nil,
                eventType: .bolus
            )))
            #expect(BaseNightscoutManager.uploadStillCurrent(event, self.nsTreatment(
                insulin: 2.4,
                rate: nil,
                duration: nil,
                eventType: .bolus
            )))
        }
    }

    @Test("Upload stamp verification covers temp basal rate and duration") func testUploadStampVerifiesTempBasal() async throws {
        try await testContext.perform {
            let event = PumpEventStored(context: testContext)
            event.id = "race-row"
            event.timestamp = Date()
            event.type = PumpEvent.tempBasal.rawValue
            let tempBasal = TempBasalStored(context: testContext)
            tempBasal.rate = 1.2 as NSDecimalNumber
            tempBasal.duration = 20
            tempBasal.pumpEvent = event
            try testContext.save()

            #expect(BaseNightscoutManager.uploadStillCurrent(event, self.nsTreatment(
                insulin: nil,
                rate: 1.2,
                duration: 20,
                eventType: .tempBasal
            )))
            // cancelled early while the 30 min POST was in flight
            #expect(!BaseNightscoutManager.uploadStillCurrent(event, self.nsTreatment(
                insulin: nil,
                rate: 1.2,
                duration: 30,
                eventType: .tempBasal
            )))
        }
    }
}
