import Combine
import CoreData
import Foundation
import LoopKit
import Swinject
import Testing

@testable import LoopKit
@testable import MockKit
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

    @Test("Accompanying suspend and resume doses on rewind/prime persist alongside primary events")
    func testAccompanyingSuspendAndResumeDosesPersist() async throws {
        let now = Date()
        let rewindAt = now.addingTimeInterval(-40 * 60)
        let primeAt = now.addingTimeInterval(-35 * 60)

        try await storage.storePumpEvents(
            [suspendEvent(rewindAt, raw: "mm-rewind", type: .rewind), resumeEvent(primeAt, raw: "mm-prime", type: .prime)],
            replacePendingEvents: false
        )

        let types = try await fetchAllEvents().compactMap(\.type)
        #expect(types.contains(PumpEvent.rewind.rawValue))
        #expect(types.contains(PumpEvent.pumpSuspend.rawValue))
        #expect(types.contains(PumpEvent.prime.rawValue))
        #expect(types.contains(PumpEvent.pumpResume.rawValue))
    }

    @Test("Open suspension reconciles from fresh live status or earlier delivery and re-anchors uploaded resumes")
    func testOpenSuspensionReconcilesReanchorsAndPurgesSupersededUpload() async throws {
        let now = Date()
        let suspendAt = now.addingTimeInterval(-60 * 60)
        let earlierTbrAt = suspendAt.addingTimeInterval(10 * 60)
        let statusAt = suspendAt.addingTimeInterval(25 * 60)
        let laterPrimeAt = suspendAt.addingTimeInterval(40 * 60)

        try await storage.storePumpEvents([suspendEvent(suspendAt, raw: "open-s1")], replacePendingEvents: false)

        // Stale pre-suspend confirmation cannot close a newer suspend without a fresh post-suspend sync
        let stale = try await storage.reconcileOpenSuspension(activeDeliverySince: suspendAt.addingTimeInterval(-5 * 60), now: now)
        #expect(stale == .unchanged)

        let first = try await storage.reconcileOpenSuspension(activeDeliverySince: statusAt, now: now)
        #expect(first.didReconcile == true)
        #expect(try await resumeTimestamps() == [statusAt])

        // Repeated poll with same confirmation is idempotent
        let repeated = try await storage.reconcileOpenSuspension(activeDeliverySince: statusAt, now: now.addingTimeInterval(60))
        #expect(repeated == .unchanged)

        let uploadedId: String = try await testContext.perform {
            let row = try #require(try testContext.fetch(PumpEventStored.fetchRequest()).first {
                $0.type == PumpEvent.pumpResume.rawValue
            })
            row.isUploadedToNS = true
            try testContext.save()
            return row.id ?? ""
        }

        // Earlier delivery + later companion Prime resume: keeps both earlier delivery anchor and Prime resume, purging stale NS ID
        let purged = try await storage.storePumpEvents(
            [
                tempBasalEvent(start: earlierTbrAt, end: earlierTbrAt.addingTimeInterval(15 * 60), raw: "earlier-tbr"),
                resumeEvent(laterPrimeAt, raw: "later-prime", type: .prime)
            ],
            replacePendingEvents: false
        )
        #expect(purged == [uploadedId])
        #expect(try await resumeTimestamps() == [earlierTbrAt, laterPrimeAt])
    }

    @Test("Multi-suspend batches split intermediate gaps, promote matching hardware resumes, and transfer status across nested rewind")
    func testMultiSuspendGapsPromotionAndNestedRewindTransfer() async throws {
        let now = Date()
        let firstSuspend = now.addingTimeInterval(-120 * 60)
        let nestedRewind = firstSuspend.addingTimeInterval(10 * 60)
        let statusAt = firstSuspend.addingTimeInterval(15 * 60)
        let secondSuspend = firstSuspend.addingTimeInterval(45 * 60)
        let midTbrStart = firstSuspend.addingTimeInterval(60 * 60)
        let thirdSuspend = firstSuspend.addingTimeInterval(90 * 60)

        try await storage.storePumpEvents([suspendEvent(firstSuspend, raw: "s1")], replacePendingEvents: false)
        _ = try await storage.reconcileOpenSuspension(activeDeliverySince: statusAt, now: now)

        // Nested rewind at +10m transfers +15m status confirmation; intermediate TBR splits [secondSuspend, thirdSuspend]
        try await storage.storePumpEvents(
            [
                suspendEvent(nestedRewind, raw: "nested-rw", type: .rewind),
                suspendEvent(secondSuspend, raw: "s2"),
                tempBasalEvent(start: midTbrStart, end: midTbrStart.addingTimeInterval(15 * 60), raw: "mid-tbr"),
                suspendEvent(thirdSuspend, raw: "s3")
            ],
            replacePendingEvents: false
        )
        #expect(try await resumeTimestamps() == [statusAt, midTbrStart])

        // Hardware resume arriving at exact statusAt promotes provenance cleanly
        try await storage.storePumpEvents([resumeEvent(statusAt, raw: "hw-r-exact")], replacePendingEvents: false)
        let promoted = try await fetchAllEvents().first { $0.timestamp == statusAt && $0.type == PumpEvent.pumpResume.rawValue }
        #expect(promoted?.syncIdentifier == storedIdentifier("hw-r-exact"))
        #expect(promoted?.note == nil)
    }

    @Test("Withdrawn pending delivery or zero-delivered bolus retracts unconfirmed derived resumes")
    func testWithdrawnOrZeroDeliveredDosesRetractDerivedResume() async throws {
        let now = Date()
        let s1 = now.addingTimeInterval(-90 * 60)
        let pendingTbrAt = s1.addingTimeInterval(15 * 60)
        let s2 = s1.addingTimeInterval(45 * 60)
        let failedBolusAt = s2.addingTimeInterval(10 * 60)

        try await storage.storePumpEvents(
            [
                suspendEvent(s1, raw: "retract-s1"),
                tempBasalEvent(start: pendingTbrAt, end: pendingTbrAt.addingTimeInterval(20 * 60), raw: "pending-tbr", isMutable: true),
                suspendEvent(s2, raw: "retract-s2"),
                bolusEvent(failedBolusAt, units: 1.0, raw: "zero-bolus", isMutable: true)
            ],
            replacePendingEvents: false
        )
        #expect(try await resumeTimestamps() == [pendingTbrAt, failedBolusAt])

        // Complete pending report withdraws pending-tbr and finalizes zero-bolus to 0 U
        try await storage.storePumpEvents(
            [bolusEvent(failedBolusAt, units: 1.0, deliveredUnits: 0.0, raw: "zero-bolus", isMutable: false)],
            replacePendingEvents: true
        )
        #expect(try await resumeTimestamps().isEmpty)
    }

    @Test("DeviceDataManager heartbeat reconciles open suspension before emitting recommendsLoop")
    func testHeartbeatReconcilesBeforeRecommendingLoop() async throws {
        var deviceDataManager = resolver.resolve(DeviceDataManager.self)!
        let mockPump = MockPumpManager()
        defer { deviceDataManager.pumpManager = nil }

        let rewindDate = Date().addingTimeInterval(-10 * 60)
        mockPump.state.additionalPumpEvents = [suspendEvent(rewindDate, raw: "hb-rewind", type: .rewind)]
        deviceDataManager.pumpManager = mockPump

        var cancellable: AnyCancellable?
        await withCheckedContinuation { continuation in
            cancellable = deviceDataManager.recommendsLoop.first().sink { continuation.resume() }
            deviceDataManager.heartbeat(date: Date())
        }
        _ = cancellable

        let resumes = try await resumeTimestamps()
        #expect(resumes.contains { $0 > rewindDate })
    }
}
