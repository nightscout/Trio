import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("TempTargetStorage Tests", .serialized) struct TempTargetsStorageTests: Injectable {
    @Injected() var storage: TempTargetsStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        // Create test context
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()

        // Create assembler with test assembly
        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext) // Add our test assembly last to override TempTargetStorage
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        // Verify storage exists
        #expect(storage != nil, "TempTargetsStorage should be injected")

        // Verify it's the correct type
        #expect(
            storage is BaseTempTargetsStorage, "Storage should be of type BaseTempTargetsStorage"
        )
    }

    @Test("Store and retrieve temp target") func testStoreAndRetrieveTempTarget() async throws {
        // Given
        let testTarget = TempTarget(
            name: "Test Target",
            createdAt: Date(),
            targetTop: 120,
            targetBottom: 120,
            duration: 60,
            enteredBy: "Test",
            reason: "Testing",
            isPreset: false,
            halfBasalTarget: 160
        )

        // When
        try await storage.storeTempTarget(tempTarget: testTarget)

        // Then verify stored entries
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Test Target"),
            key: "date",
            ascending: false
        ) as? [TempTargetStored]

        #expect(storedEntries?.isEmpty == false, "Should have stored entries")
        #expect(storedEntries?.count == 1, "Should have exactly one entry")
        let storedTarget = storedEntries?.first
        #expect(storedTarget?.name == "Test Target", "Name should match")
        #expect(storedTarget?.target == 120, "Target should match")
        #expect(storedTarget?.duration == 60, "Duration should match")
    }

    @Test("Delete temp target Preset") func testDeleteTempTarget() async throws {
        // Given
        let testTarget = TempTarget(
            name: "Delete Test",
            createdAt: Date(),
            targetTop: 120,
            targetBottom: 120,
            duration: 60,
            enteredBy: "Test",
            reason: "Testing deletion of a preset",
            isPreset: true,
            halfBasalTarget: 160
        )
        // Store the target
        try await storage.storeTempTarget(tempTarget: testTarget)

        // Get the stored target's ObjectID
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Delete Test"),
            key: "date",
            ascending: false
        ) as? [TempTargetStored]

        guard let objectID = storedEntries?.first?.objectID else {
            throw TestError("Failed to get stored target's ObjectID")
        }

        // When
        await storage.deleteTempTargetPreset(objectID)

        // Then verify deletion
        let remainingEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Delete Test"),
            key: "date",
            ascending: false
        ) as? [TempTargetStored]

        #expect(remainingEntries?.isEmpty == true, "Should have no entries after deletion")
    }

    @Test("Get temp targets not yet uploaded to Nightscout") func testGetTempTargetsNotYetUploadedToNightscout() async throws {
        // Given
        let testTarget = TempTarget(
            name: "NS Test",
            createdAt: Date(),
            targetTop: 120,
            targetBottom: 120,
            duration: 45,
            enteredBy: "Test",
            reason: "Testing NS Upload",
            isPreset: true,
            enabled: true,
            halfBasalTarget: 160
        )

        // When
        try await storage.storeTempTarget(tempTarget: testTarget)
        let notUploadedTargets = try await storage.getTempTargetsNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedTargets.isEmpty, "Should have targets not uploaded to NS")
        let target = notUploadedTargets[0]
        #expect(target.eventType == .nsTempTarget, "Event type should be NS temp target")
        #expect(target.duration == 45, "Duration should match")
        #expect(target.targetTop == 120, "Target top should match target")
        #expect(target.targetBottom == 120, "Target bottom should match target")
    }

    @Test("Get temp target runs not yet uploaded to Nightscout") func testGetTempTargetRunsNotYetUploadedToNightscout() async throws {
        // Given
        let now = Date()
        let hour: TimeInterval = 60 * 60
        let recentStart = now.addingTimeInterval(-2 * hour)
        let longRunningStart = now.addingTimeInterval(-72 * hour)

        await testContext.perform {
            let recent = TempTargetRunStored(context: self.testContext)
            recent.id = UUID()
            recent.name = "Recent"
            recent.startDate = recentStart
            recent.endDate = now.addingTimeInterval(-hour)
            recent.target = 140
            recent.isUploadedToNS = false

            let longRunning = TempTargetRunStored(context: self.testContext)
            longRunning.id = UUID()
            longRunning.name = "Long running"
            longRunning.startDate = longRunningStart
            longRunning.endDate = now.addingTimeInterval(-hour)
            longRunning.target = 140
            longRunning.isUploadedToNS = false

            let stale = TempTargetRunStored(context: self.testContext)
            stale.id = UUID()
            stale.name = "Stale"
            stale.startDate = now.addingTimeInterval(-72 * hour)
            stale.endDate = now.addingTimeInterval(-48 * hour)
            stale.target = 140
            stale.isUploadedToNS = false

            let uploaded = TempTargetRunStored(context: self.testContext)
            uploaded.id = UUID()
            uploaded.name = "Uploaded"
            uploaded.startDate = recentStart
            uploaded.endDate = now.addingTimeInterval(-hour)
            uploaded.target = 140
            uploaded.isUploadedToNS = true

            try? self.testContext.save()
        }

        // When
        let runs = try await storage.getTempTargetRunsNotYetUploadedToNightscout()

        // Then
        #expect(
            Set(runs.compactMap(\.createdAt)) == [recentStart, longRunningStart],
            "Runs that ended within the last day are uploaded, whenever they started"
        )

        let longRunning = try #require(runs.first { $0.createdAt == longRunningStart })
        #expect(longRunning.duration == 71 * 60, "Duration spans the whole run")
        #expect(longRunning.eventType == .nsTempTarget, "Event type should be NS temp target")
    }

    @Test(
        "Main chart predicate excludes presets saved after the predicate was built"
    ) func testMainChartPredicateExcludesNewPresets() async throws {
        // Given a predicate anchored before the entries exist, like the chart controller keeps between foregrounds
        let anchoredPredicate = NSPredicate.tempTargetsForMainChart

        let preset = TempTarget(
            name: "Chart Preset",
            createdAt: Date(),
            targetTop: 80,
            targetBottom: 80,
            duration: 20,
            enteredBy: "Test",
            reason: "Testing chart predicate",
            isPreset: true,
            enabled: false,
            halfBasalTarget: 160
        )
        let scheduled = TempTarget(
            name: "Chart Scheduled",
            createdAt: Date().addingTimeInterval(3600),
            targetTop: 90,
            targetBottom: 90,
            duration: 30,
            enteredBy: "Test",
            reason: "Testing chart predicate",
            isPreset: false,
            enabled: false,
            halfBasalTarget: 160
        )
        let running = TempTarget(
            name: "Chart Running",
            createdAt: Date(),
            targetTop: 135,
            targetBottom: 135,
            duration: 120,
            enteredBy: "Test",
            reason: "Testing chart predicate",
            isPreset: false,
            enabled: true,
            halfBasalTarget: 160
        )

        // When
        try await storage.storeTempTarget(tempTarget: preset)
        try await storage.storeTempTarget(tempTarget: scheduled)
        try await storage.storeTempTarget(tempTarget: running)

        // Then
        let matches = try await coreDataStack.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: testContext,
            predicate: anchoredPredicate,
            key: "date",
            ascending: false
        ) as? [TempTargetStored]

        let names = matches?.map(\.name)
        #expect(names?.contains("Chart Preset") == false, "Never activated preset should not match the chart predicate")
        #expect(names?.contains("Chart Scheduled") == true, "Scheduled temp target should match the chart predicate")
        #expect(names?.contains("Chart Running") == true, "Running temp target should match the chart predicate")
    }

    @Test("Chart visibility keeps running and scheduled temp targets only") func testIsVisibleInChart() async throws {
        await testContext.perform {
            let preset = TempTargetStored(context: testContext)
            preset.date = Date()
            preset.enabled = false
            preset.isPreset = true

            let enactedPreset = TempTargetStored(context: testContext)
            enactedPreset.date = Date()
            enactedPreset.enabled = true
            enactedPreset.isPreset = true

            let scheduled = TempTargetStored(context: testContext)
            scheduled.date = Date().addingTimeInterval(3600)
            scheduled.enabled = false
            scheduled.isPreset = false

            let running = TempTargetStored(context: testContext)
            running.date = Date()
            running.enabled = true
            running.isPreset = false

            let cancelled = TempTargetStored(context: testContext)
            cancelled.date = Date().addingTimeInterval(-600)
            cancelled.enabled = false
            cancelled.isPreset = false

            #expect(!preset.isVisibleInChart, "Never activated preset should not be visible")
            #expect(enactedPreset.isVisibleInChart, "Enacted preset should be visible")
            #expect(scheduled.isVisibleInChart, "Scheduled temp target should be visible")
            #expect(running.isVisibleInChart, "Running temp target should be visible")
            #expect(!cancelled.isVisibleInChart, "Cancelled temp target should not be visible")
        }
    }
}
