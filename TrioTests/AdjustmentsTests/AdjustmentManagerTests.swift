import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

/// Covers the transaction the manager owns: which rows end, which run entries appear, what is
/// marked for upload, and what happens when a command cannot be resolved. The determination step is
/// stubbed out in `TestAssembly`, so these tests never enter the algorithm.
@Suite("Adjustment Manager Tests", .serialized) struct AdjustmentManagerTests: Injectable {
    @Injected() var manager: AdjustmentManager!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

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

    // MARK: - Resolution

    @Test("Manager resolves from the service container") func testManagerResolves() {
        #expect(manager != nil, "AdjustmentManager should be registered in ServiceAssembly")
        #expect(manager is BaseAdjustmentManager, "Manager should be of type BaseAdjustmentManager")
    }

    @Test("Every caller shares one manager") func testManagerIsShared() {
        let first = resolver.resolve(AdjustmentManager.self)
        let second = resolver.resolve(AdjustmentManager.self)
        #expect(first != nil)
        #expect(first as AnyObject? === second as AnyObject?, "One instance means one serializer across callers")
    }

    // MARK: - Overrides

    @Test("Switching overrides records the one that ends") func testSwitchOverrideRecordsRun() async throws {
        let start = Date().addingTimeInterval(-60 * 60)
        await makeOverride(name: "Tempbasal", enabled: true, date: start)
        await makeOverride(name: "Fotboll", enabled: false, date: Date().addingTimeInterval(-24 * 60 * 60), orderPosition: 2)

        let outcome = try await manager.activateOverride(.presetName("Fotboll"), source: .watch)

        #expect(outcome.started?.name == "Fotboll")
        #expect(outcome.ended.map(\.name) == ["Tempbasal"])

        let runs = try await overrideRuns()
        #expect(runs.count == 1, "The override that ended has exactly one run entry")
        #expect(runs.first?.name == "Tempbasal")
        #expect(runs.first?.startDate == start, "The run starts when the override it records started")
        #expect(runs.first?.isUploadedToNS == false, "The run is queued for Nightscout")
        #expect(runs.first?.linkedName == "Tempbasal", "The run points at the override it records")

        let rows = try await overrides()
        #expect(rows.first(where: { $0.name == "Tempbasal" })?.enabled == false)
        let started = rows.first(where: { $0.name == "Fotboll" })
        #expect(started?.enabled == true)
        #expect(started?.isUploadedToNS == false, "The started override is queued for Nightscout")
    }

    @Test("Re-activating the running override records the elapsed segment") func testRestartOverride() async throws {
        let start = Date().addingTimeInterval(-30 * 60)
        await makeOverride(name: "Tempbasal", enabled: true, date: start)

        try await manager.activateOverride(.presetName("Tempbasal"), source: .remote)

        let runs = try await overrideRuns()
        #expect(runs.count == 1, "The elapsed segment is recorded")
        #expect(runs.first?.startDate == start)

        let rows = try await overrides()
        let row = rows.first(where: { $0.name == "Tempbasal" })
        #expect(row?.enabled == true, "The override keeps running")
        #expect((row?.date ?? .distantPast) > start, "Its start moves to the restart")
    }

    @Test("A finite override that ran out ends at its expiry") func testExpiredOverrideEndsAtExpiry() async throws {
        let start = Date().addingTimeInterval(-120 * 60)
        await makeOverride(name: "Expired", enabled: true, date: start, duration: 60, indefinite: false)

        try await manager.cancelOverride(source: .app)

        let runs = try await overrideRuns()
        let expiry = start.addingTimeInterval(60 * 60)
        #expect(runs.count == 1)
        let endDate = try #require(runs.first?.endDate)
        #expect(abs(endDate.timeIntervalSince(expiry)) < 1, "The run ends 60 minutes after it started")
    }

    @Test("Cancelling with nothing running throws and writes nothing") func testCancelNothingActive() async throws {
        await makeOverride(name: "Tempbasal", enabled: false, date: Date())

        await #expect(throws: AdjustmentError.nothingActive) {
            try await manager.cancelOverride(source: .watch)
        }

        let runs = try await overrideRuns()
        #expect(runs.isEmpty, "A rejected command writes no run entry")
    }

    @Test("An unknown preset leaves the running override untouched") func testUnknownPresetIsAtomic() async throws {
        let start = Date().addingTimeInterval(-45 * 60)
        await makeOverride(name: "Tempbasal", enabled: true, date: start)

        await #expect(throws: AdjustmentError.presetNotFound("Simning")) {
            try await manager.activateOverride(.presetName("Simning"), source: .watch)
        }

        let rows = try await overrides()
        #expect(rows.first(where: { $0.name == "Tempbasal" })?.enabled == true, "The running override stays enabled")
        let runs = try await overrideRuns()
        #expect(runs.isEmpty, "No run entry is written")
    }

    @Test("Concurrent activations leave exactly one override running") func testConcurrentActivations() async throws {
        await makeOverride(name: "Tempbasal", enabled: true, date: Date().addingTimeInterval(-60 * 60))
        await makeOverride(name: "Fotboll", enabled: false, date: Date().addingTimeInterval(-24 * 60 * 60), orderPosition: 2)
        await makeOverride(name: "Simning", enabled: false, date: Date().addingTimeInterval(-24 * 60 * 60), orderPosition: 3)

        // A context per command, so two commands reach the store independently and the serializer
        // is what keeps them in order.
        let stack = coreDataStack!
        let manager = BaseAdjustmentManager(
            resolver: resolver,
            contextProvider: { stack.newTaskContext() },
            recompute: {}
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await manager.activateOverride(.presetName("Fotboll"), source: .watch) }
            group.addTask { _ = try? await manager.activateOverride(.presetName("Simning"), source: .remote) }
            await group.waitForAll()
        }

        await testContext.perform { self.testContext.refreshAllObjects() }

        let rows = try await overrides()
        #expect(rows.filter(\.enabled).count == 1, "Commands are applied one after another")
        let runs = try await overrideRuns()
        #expect(runs.count == 2, "Each ended override is recorded once")
    }

    @Test("A stored row activates by object ID") func testActivateByObjectID() async throws {
        await makeOverride(name: "Tempbasal", enabled: true, date: Date().addingTimeInterval(-30 * 60))
        let objectID = await makeOverride(
            name: "Custom Override",
            enabled: false,
            date: Date().addingTimeInterval(-24 * 60 * 60),
            orderPosition: 2
        )

        let outcome = try await manager.activateOverride(.objectID(objectID), source: .remote)

        #expect(outcome.started?.name == "Custom Override")
        #expect(outcome.ended.map(\.name) == ["Tempbasal"])

        let rows = try await overrides()
        #expect(rows.first(where: { $0.name == "Custom Override" })?.enabled == true)
        #expect(rows.first(where: { $0.name == "Tempbasal" })?.enabled == false)
    }

    // MARK: - Temp targets

    @Test("Switching temp targets records the one that ends") func testSwitchTempTargetRecordsRun() async throws {
        let start = Date().addingTimeInterval(-20 * 60)
        await makeTempTarget(name: "Activity", enabled: true, date: start, duration: 90, target: 140)
        await makeTempTarget(
            name: "Eating Soon",
            enabled: false,
            date: Date().addingTimeInterval(-24 * 60 * 60),
            duration: 60,
            target: 80,
            orderPosition: 2
        )

        let outcome = try await manager.activateTempTarget(.presetName("Eating Soon"), source: .watch)

        #expect(outcome.started?.name == "Eating Soon")
        #expect(outcome.ended.map(\.name) == ["Activity"])

        let runs = try await tempTargetRuns()
        #expect(runs.count == 1)
        #expect(runs.first?.name == "Activity")
        #expect(runs.first?.startDate == start)
        #expect(runs.first?.isUploadedToNS == false)

        let rows = try await tempTargets()
        #expect(rows.first(where: { $0.name == "Activity" })?.enabled == false)
        #expect(rows.first(where: { $0.name == "Eating Soon" })?.enabled == true)
    }

    @Test("Cancelling a temp target records it and disables the row") func testCancelTempTarget() async throws {
        let start = Date().addingTimeInterval(-15 * 60)
        await makeTempTarget(name: "Activity", enabled: true, date: start, duration: 90, target: 140)

        let outcome = try await manager.cancelTempTarget(source: .watch)

        #expect(outcome.started == nil)
        #expect(outcome.ended.map(\.name) == ["Activity"])

        let runs = try await tempTargetRuns()
        #expect(runs.count == 1)
        #expect(runs.first?.startDate == start)
        #expect(runs.first?.linkedName == "Activity", "The run points at the temp target it records")

        let rows = try await tempTargets()
        #expect(rows.first(where: { $0.name == "Activity" })?.enabled == false)
    }

    @Test("Cancelling a temp target with nothing running throws") func testCancelTempTargetNothingActive() async throws {
        await makeTempTarget(name: "Activity", enabled: false, date: Date(), duration: 90, target: 140)

        await #expect(throws: AdjustmentError.nothingActive) {
            try await manager.cancelTempTarget(source: .watch)
        }

        let runs = try await tempTargetRuns()
        #expect(runs.isEmpty, "A rejected command writes no run entry")
    }

    // MARK: - Fixtures

    @discardableResult private func makeOverride(
        name: String,
        enabled: Bool,
        date: Date,
        duration: Decimal = 0,
        indefinite: Bool = true,
        orderPosition: Int16 = 1
    ) async -> NSManagedObjectID {
        await testContext.perform {
            let row = OverrideStored(context: self.testContext)
            row.id = UUID().uuidString
            row.name = name
            row.enabled = enabled
            row.date = date
            row.duration = NSDecimalNumber(decimal: duration)
            row.indefinite = indefinite
            row.isPreset = true
            row.orderPosition = orderPosition
            row.percentage = 100
            row.isUploadedToNS = true
            try? self.testContext.save()
            return row.objectID
        }
    }

    @discardableResult private func makeTempTarget(
        name: String,
        enabled: Bool,
        date: Date,
        duration: Decimal,
        target: Decimal,
        orderPosition: Int16 = 1
    ) async -> NSManagedObjectID {
        await testContext.perform {
            let row = TempTargetStored(context: self.testContext)
            row.id = UUID()
            row.name = name
            row.enabled = enabled
            row.date = date
            row.duration = NSDecimalNumber(decimal: duration)
            row.target = NSDecimalNumber(decimal: target)
            row.isPreset = true
            row.orderPosition = orderPosition
            row.enteredBy = TempTarget.local
            row.isUploadedToNS = true
            try? self.testContext.save()
            return row.objectID
        }
    }

    // MARK: - Snapshots

    //
    // Values are read on the context's own queue and handed back as plain structs.

    private struct RowSnapshot {
        let name: String?
        let enabled: Bool
        let date: Date?
        let isUploadedToNS: Bool
    }

    private struct RunSnapshot {
        let name: String?
        let startDate: Date?
        let endDate: Date?
        let isUploadedToNS: Bool
        /// Name of the row the run points at; the Nightscout payload reads it through this
        /// relationship.
        let linkedName: String?
    }

    private func overrides() async throws -> [RowSnapshot] {
        try await testContext.perform {
            let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            return try self.testContext.fetch(request).map {
                RowSnapshot(name: $0.name, enabled: $0.enabled, date: $0.date, isUploadedToNS: $0.isUploadedToNS)
            }
        }
    }

    private func tempTargets() async throws -> [RowSnapshot] {
        try await testContext.perform {
            let request: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            return try self.testContext.fetch(request).map {
                RowSnapshot(name: $0.name, enabled: $0.enabled, date: $0.date, isUploadedToNS: $0.isUploadedToNS)
            }
        }
    }

    private func overrideRuns() async throws -> [RunSnapshot] {
        try await testContext.perform {
            let request: NSFetchRequest<OverrideRunStored> = OverrideRunStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
            return try self.testContext.fetch(request).map {
                RunSnapshot(
                    name: $0.name,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isUploadedToNS: $0.isUploadedToNS,
                    linkedName: $0.override?.name
                )
            }
        }
    }

    private func tempTargetRuns() async throws -> [RunSnapshot] {
        try await testContext.perform {
            let request: NSFetchRequest<TempTargetRunStored> = TempTargetRunStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
            return try self.testContext.fetch(request).map {
                RunSnapshot(
                    name: $0.name,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isUploadedToNS: $0.isUploadedToNS,
                    linkedName: $0.tempTarget?.name
                )
            }
        }
    }
}
