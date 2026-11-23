import CoreData
import Foundation
import LoopKit
import Swinject
import Testing

@testable import LoopKit
@testable import Trio

@Suite("Pump Suspension Reconciliation Tests", .serialized) struct PumpSuspensionReconciliationTests: Injectable {
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

    private func storedIdentifier(_ raw: String) -> String {
        Data(raw.utf8).hexadecimalString
    }

    private func suspendEvent(_ date: Date, raw: String, type: PumpEventType = .suspend) -> NewPumpEvent {
        NewPumpEvent(date: date, dose: DoseEntry(suspendDate: date), raw: Data(raw.utf8), title: "Suspend", type: type)
    }

    private func resumeEvent(_ date: Date, raw: String, type: PumpEventType = .resume) -> NewPumpEvent {
        NewPumpEvent(date: date, dose: DoseEntry(resumeDate: date), raw: Data(raw.utf8), title: "Resume", type: type)
    }

    private func bolusEvent(
        _ date: Date,
        units: Double,
        deliveredUnits: Double? = nil,
        raw: String,
        isMutable: Bool = false
    ) -> NewPumpEvent {
        NewPumpEvent(
            date: date,
            dose: DoseEntry(
                type: .bolus,
                startDate: date,
                value: units,
                unit: .units,
                decisionId: nil,
                deliveredUnits: deliveredUnits,
                description: nil,
                syncIdentifier: raw,
                scheduledBasalRate: nil,
                insulinType: .lyumjev,
                automatic: true,
                manuallyEntered: false,
                isMutable: isMutable
            ),
            raw: Data(raw.utf8),
            title: "Bolus",
            type: .bolus
        )
    }

    private func tempBasalEvent(
        start: Date,
        end: Date,
        rate: Double = 1.0,
        raw: String,
        isMutable: Bool = false
    ) -> NewPumpEvent {
        NewPumpEvent(
            date: start,
            dose: DoseEntry(
                type: .tempBasal,
                startDate: start,
                endDate: end,
                value: rate,
                unit: .unitsPerHour,
                decisionId: nil,
                deliveredUnits: nil,
                description: nil,
                syncIdentifier: raw,
                scheduledBasalRate: nil,
                insulinType: .lyumjev,
                automatic: true,
                manuallyEntered: false,
                isMutable: isMutable
            ),
            raw: Data(raw.utf8),
            title: "TempBasal",
            type: .tempBasal
        )
    }

    private func fetchAllEvents() async throws -> [PumpEventStored] {
        try await testContext.perform {
            let req = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
            req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            return try testContext.fetch(req).filter { !$0.isDeleted }
        }
    }

    private func resumeTimestamps() async throws -> [Date] {
        try await fetchAllEvents()
            .filter { $0.type == PumpEvent.pumpResume.rawValue }
            .compactMap(\.timestamp)
            .sorted()
    }

    @Test("Accompanying suspend/resume doses on rewind, prime, alarm, and alarmClear persist and collapse nested suspends")
    func testAccompanyingDosesAndNestedSuspendCollapse() async throws {
        let now = Date()
        let manualSuspend = now.addingTimeInterval(-50 * 60)
        let rewindAt = now.addingTimeInterval(-40 * 60)
        let primeAt = now.addingTimeInterval(-35 * 60)
        let alarmAt = now.addingTimeInterval(-20 * 60)
        let clearAt = now.addingTimeInterval(-15 * 60)

        try await storage.storePumpEvents(
            [
                suspendEvent(manualSuspend, raw: "mm-manual-suspend"),
                suspendEvent(rewindAt, raw: "mm-rewind", type: .rewind),
                resumeEvent(primeAt, raw: "mm-prime", type: .prime),
                suspendEvent(alarmAt, raw: "mm-no-delivery", type: .alarm),
                resumeEvent(clearAt, raw: "mm-clear-alarm", type: .alarmClear)
            ],
            replacePendingEvents: false
        )

        let stored = try await fetchAllEvents()
        let types = stored.compactMap(\.type)
        #expect(types.contains(PumpEvent.rewind.rawValue))
        #expect(types.contains(PumpEvent.prime.rawValue))
        #expect(types.contains(PumpEvent.pumpAlarm.rawValue))

        let suspends = stored.filter { $0.type == PumpEvent.pumpSuspend.rawValue }
            .compactMap { $0.timestamp.map { PumpHistoryEvent(id: UUID().uuidString, type: .pumpSuspend, timestamp: $0) } }
        let resumes = stored.filter { $0.type == PumpEvent.pumpResume.rawValue }
            .compactMap { $0.timestamp.map { PumpHistoryEvent(id: UUID().uuidString, type: .pumpResume, timestamp: $0) } }
        #expect(resumes.map(\.timestamp) == [primeAt, clearAt])

        let spans = BaseTDDStorage.suspensionSpans(suspends: suspends, resumes: resumes, now: now)
        #expect(spans.count == 2)
        #expect(spans.first?.start == manualSuspend && spans.first?.end == primeAt)
        #expect(spans.last?.start == alarmAt && spans.last?.end == clearAt)
    }

    @Test("Post-suspend delivery closes missing resumes, re-anchors on earlier delivery, and promotes matching hardware resumes")
    func testMissingResumeClosedByDeliveryReanchorsAndPromotes() async throws {
        let now = Date()
        let s1 = now.addingTimeInterval(-90 * 60)
        let earlierTbrAt = s1.addingTimeInterval(10 * 60)
        let initialTbrAt = s1.addingTimeInterval(25 * 60)
        let s2 = s1.addingTimeInterval(50 * 60)
        let bolusAt = s1.addingTimeInterval(60 * 60)

        try await storage.storePumpEvents(
            [
                suspendEvent(s1, raw: "gap-s1"),
                tempBasalEvent(start: initialTbrAt, end: initialTbrAt.addingTimeInterval(15 * 60), raw: "initial-tbr"),
                suspendEvent(s2, raw: "gap-s2"),
                bolusEvent(bolusAt, units: 0.5, raw: "post-s2-bolus")
            ],
            replacePendingEvents: false
        )
        #expect(try await resumeTimestamps() == [initialTbrAt, bolusAt])

        let resumeTreatment = try #require(
            try await storage.getPumpHistoryNotYetUploadedToNightscout()
                .first { $0.notes == PumpEvent.pumpResume.rawValue && $0.createdAt == initialTbrAt }
        )
        let uploadedId = try #require(resumeTreatment.id)
        try await testContext.perform {
            let row = try #require(try testContext.fetch(PumpEventStored.fetchRequest()).first { $0.id == uploadedId })
            #expect(BaseNightscoutManager.uploadStillCurrent(row, resumeTreatment))
            row.isUploadedToNS = true
            try testContext.save()
        }

        // Delayed earlier delivery re-anchors s1's resume and returns the superseded Nightscout ID
        let purged = try await storage.storePumpEvents(
            [tempBasalEvent(start: earlierTbrAt, end: earlierTbrAt.addingTimeInterval(10 * 60), raw: "earlier-tbr")],
            replacePendingEvents: false
        )
        #expect(purged == [uploadedId])
        #expect(try await resumeTimestamps() == [earlierTbrAt, bolusAt])

        // Hardware resume arriving at the exact derived timestamp promotes provenance cleanly
        try await storage.storePumpEvents([resumeEvent(earlierTbrAt, raw: "hw-exact-resume")], replacePendingEvents: false)
        let promoted = try await fetchAllEvents().first { $0.timestamp == earlierTbrAt && $0.type == PumpEvent.pumpResume.rawValue }
        #expect(promoted?.syncIdentifier == storedIdentifier("hw-exact-resume"))
    }

    @Test("Withdrawn pending delivery or zero-delivered bolus retracts derived resumes")
    func testWithdrawnOrZeroDeliveredDosesRetractDerivedResume() async throws {
        let now = Date()
        let s1 = now.addingTimeInterval(-60 * 60)
        let pendingTbrAt = s1.addingTimeInterval(10 * 60)
        let s2 = s1.addingTimeInterval(30 * 60)
        let failedBolusAt = s2.addingTimeInterval(10 * 60)

        try await storage.storePumpEvents(
            [
                suspendEvent(s1, raw: "retract-s1"),
                tempBasalEvent(start: pendingTbrAt, end: pendingTbrAt.addingTimeInterval(15 * 60), raw: "pending-tbr", isMutable: true),
                suspendEvent(s2, raw: "retract-s2"),
                bolusEvent(failedBolusAt, units: 1.0, raw: "zero-bolus", isMutable: true)
            ],
            replacePendingEvents: false
        )
        #expect(try await resumeTimestamps() == [pendingTbrAt, failedBolusAt])

        try await storage.storePumpEvents(
            [bolusEvent(failedBolusAt, units: 1.0, deliveredUnits: 0.0, raw: "zero-bolus", isMutable: false)],
            replacePendingEvents: true
        )
        #expect(try await resumeTimestamps().isEmpty)
    }
}
