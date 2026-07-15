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

    @Test("Insulin model snapshot is stored per event") func testInsulinSnapshotStored() async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)

        try await storage.storePumpEvents(
            [bolusEvent(date: date, units: 1.0, deliveredUnits: 1.0, syncIdentifier: "bolus-snap", isMutable: false)],
            replacePendingEvents: false
        )

        let settings = resolver.resolve(SettingsManager.self)!
        let events = try await fetchAllEvents()
        let row = events.first
        #expect(row?.insulinType == Int16(LoopKit.InsulinType.lyumjev.rawValue), "Pump-reported insulin type must be stored")
        #expect(row?.actionDuration as? Decimal == settings.pumpSettings.insulinActionCurve, "DIA snapshot must match settings")
        #expect(row?.peakTime as? Decimal == 75, "Default rapid-acting peak is 75 min")
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
        #expect(row?.insulinType == -1, "Insulin type is unknown for doses external to the pump")
        #expect(row?.actionDuration != nil, "External doses still snapshot the insulin model")
    }
}
