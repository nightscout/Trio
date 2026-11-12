import CoreData
import Foundation
import Swinject
import Testing

@testable import LoopKit
@testable import Trio

/// Store-level regression tests for the pump-history fetch predicates.
@Suite("Pump Event Predicate Tests", .serialized) struct PumpEventPredicateTests: Injectable {
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

    // MARK: - Helpers

    private func bolusEvent(date: Date) -> LoopKit.NewPumpEvent {
        LoopKit.NewPumpEvent(
            date: date,
            dose: LoopKit.DoseEntry(
                type: .bolus,
                startDate: date,
                value: 1.0,
                unit: .units,
                decisionId: nil,
                deliveredUnits: 1.0,
                description: nil,
                syncIdentifier: "predicate-bolus",
                scheduledBasalRate: nil,
                insulinType: .lyumjev,
                automatic: false,
                manuallyEntered: false,
                isMutable: false
            ),
            raw: Data("predicate-bolus".utf8),
            title: "Test Bolus",
            type: .bolus
        )
    }

    private func scheduledBasalEvent(start: Date, end: Date) -> LoopKit.NewPumpEvent {
        LoopKit.NewPumpEvent(
            date: start,
            dose: LoopKit.DoseEntry(
                type: .basal,
                startDate: start,
                endDate: end,
                value: 0.8,
                unit: .unitsPerHour,
                decisionId: nil,
                deliveredUnits: nil,
                description: nil,
                syncIdentifier: "predicate-sbr",
                scheduledBasalRate: nil,
                insulinType: .lyumjev,
                automatic: true,
                manuallyEntered: false,
                isMutable: false
            ),
            raw: Data("predicate-sbr".utf8),
            title: "Scheduled Basal",
            type: .basal
        )
    }

    /// A temp basal row as it exists after lightweight migration from a
    /// pre-PR store: the new columns are backfilled with their NO defaults.
    private func insertLegacyTempBasal(timestamp: Date) async throws {
        try await testContext.perform {
            let event = PumpEventStored(context: testContext)
            event.id = UUID().uuidString
            event.timestamp = timestamp
            event.type = PumpEvent.tempBasal.rawValue
            event.isUploadedToNS = false
            event.isUploadedToHealth = false
            event.isUploadedToTidepool = false

            let tempBasal = TempBasalStored(context: testContext)
            tempBasal.rate = 1.5 as NSDecimalNumber
            tempBasal.duration = 30
            tempBasal.tempType = PumpEventStored.TempType.absolute.rawValue
            tempBasal.pumpEvent = event

            try testContext.save()
        }
    }

    private func fetchTypes(_ predicate: NSPredicate) async throws -> [String] {
        try await testContext.perform {
            try testContext.fetch(PumpEventStored.fetch(predicate, ascending: false))
                .compactMap(\.type)
        }
    }

    // MARK: - Tests

    @Test("Autosens retains a resume with a paired suspend before the old inspection window")
    func testAutosensResumeInspectionWindow() async throws {
        let now = Date()
        let resumeID = try await testContext.perform {
            let suspend = PumpEventStored(context: self.testContext)
            suspend.id = "suspend-50"
            suspend.timestamp = now.addingTimeInterval(-50 * 3600)
            suspend.type = PumpEvent.pumpSuspend.rawValue
            let resume = PumpEventStored(context: self.testContext)
            resume.id = "resume-30"
            resume.timestamp = now.addingTimeInterval(-30 * 3600)
            resume.type = PumpEvent.pumpResume.rawValue
            try self.testContext.save()
            return resume.objectID
        }

        let orphanedResumes = try await OpenAPS.fetchOrphanedResumes(on: testContext, lookbackHours: 60)
        #expect(!orphanedResumes.contains(resumeID))

        let shorterWindow = try await OpenAPS.fetchOrphanedResumes(on: testContext)
        #expect(shorterWindow.contains(resumeID), "The original window misses this resume's matching suspend")
    }

    @Test("Autosens includes insulin before its 24-hour glucose window") func testAutosensHistoryWindow() async throws {
        let now = Date()
        try await testContext.perform {
            for hoursAgo in [1, 25, 35, 37] {
                let event = PumpEventStored(context: self.testContext)
                event.id = "history-\(hoursAgo)"
                event.timestamp = now.addingTimeInterval(-Double(hoursAgo) * 3600)
                event.type = PumpEvent.bolus.rawValue
            }
            let scheduledEvent = PumpEventStored(context: self.testContext)
            scheduledEvent.id = "scheduled-25"
            scheduledEvent.timestamp = now.addingTimeInterval(-25 * 3600)
            scheduledEvent.type = PumpEvent.tempBasal.rawValue
            let scheduledBasal = TempBasalStored(context: self.testContext)
            scheduledBasal.isScheduledBasal = true
            scheduledBasal.pumpEvent = scheduledEvent
            try self.testContext.save()

            let events = try self.testContext.fetch(PumpEventStored.fetch(.pumpHistoryForAutosens, ascending: false))
            #expect(Set(events.compactMap(\.id)) == ["history-1", "history-25", "history-35"])

            let ordinaryEvents = try self.testContext.fetch(PumpEventStored.fetch(.pumpHistoryLast1440Minutes, ascending: false))
            #expect(ordinaryEvents.compactMap(\.id) == ["history-1"])
        }
    }

    @Test("Bolus rows survive the scheduled-basal exclusion in the oref fetch window") func testBolusSurvivesOrefPredicate(
    ) async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)
        try await storage.storePumpEvents([bolusEvent(date: date)], replacePendingEvents: false)

        let types = try await fetchTypes(NSPredicate.pumpHistoryLast1440Minutes)
        #expect(types.contains(PumpEvent.bolus.rawValue), "Bolus must be part of the oref pump history input")
    }

    @Test(
        "Legacy temp basals survive the exclusion clauses after migration backfill"
    ) func testLegacyTempBasalSurvivesOrefPredicate() async throws {
        let date = Date().addingTimeInterval(-10.minutes.timeInterval)
        try await insertLegacyTempBasal(timestamp: date)

        let types = try await fetchTypes(NSPredicate.pumpHistoryLast1440Minutes)
        #expect(
            types.contains(PumpEvent.tempBasal.rawValue),
            "Pre-migration temp basal rows must not vanish from the oref pump history input"
        )
    }

    @Test("Bolus rows are still selected for the Nightscout upload") func testBolusSurvivesNightscoutUploadPredicate(
    ) async throws {
        let date = Date().addingTimeInterval(-5.minutes.timeInterval)
        try await storage.storePumpEvents([bolusEvent(date: date)], replacePendingEvents: false)

        let types = try await fetchTypes(NSPredicate.pumpEventsNotYetUploadedToNightscout)
        #expect(types.contains(PumpEvent.bolus.rawValue), "Boluses must be uploaded to Nightscout")
    }

    @Test(
        "Legacy rows survive the Health/Tidepool upload predicates"
    ) func testLegacyRowsSurviveUploadPredicates(
    ) async throws {
        let date = Date().addingTimeInterval(-10.minutes.timeInterval)
        try await insertLegacyTempBasal(timestamp: date)

        let healthTypes = try await fetchTypes(NSPredicate.pumpEventsNotYetUploadedToHealth)
        let tidepoolTypes = try await fetchTypes(NSPredicate.pumpEventsNotYetUploadedToTidepool)
        #expect(healthTypes.contains(PumpEvent.tempBasal.rawValue), "Legacy rows must upload to Health")
        #expect(tidepoolTypes.contains(PumpEvent.tempBasal.rawValue), "Legacy rows must upload to Tidepool")
    }

    @Test("Scheduled-basal rows are excluded, regular temp basals are kept (control)") func testScheduledBasalExclusionStillWorks(
    ) async throws {
        let start = Date().addingTimeInterval(-30.minutes.timeInterval)
        try await storage.storePumpEvents(
            [scheduledBasalEvent(start: start, end: start.addingTimeInterval(15.minutes.timeInterval))],
            replacePendingEvents: false
        )

        let types = try await fetchTypes(NSPredicate.pumpHistoryLast1440Minutes)
        #expect(
            !types.contains(PumpEvent.tempBasal.rawValue),
            "Pump-reported scheduled basal must stay excluded from the oref input"
        )
    }
}
