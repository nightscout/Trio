import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("Override Storage Tests", .serialized) struct OverrideStorageTests: Injectable {
    @Injected() var storage: OverrideStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        // Create test context
        // As we are only using this single test context to initialize our in-memory DeterminationStorage we need to perform the Unit Tests serialized
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
            TestAssembly(testContext: testContext) // Add our test assembly last to override Storage
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        // Verify storage exists
        #expect(storage != nil, "OverrideStorage should be injected")

        // Verify it's the correct type
        #expect(storage is BaseOverrideStorage, "Storage should be of type BaseOverrideStorage")
    }

    @Test("Store and retrieve override") func testStoreAndRetrieveOverride() async throws {
        // Given
        let testOverride = Override(
            name: "Test Override",
            enabled: false,
            date: Date(),
            duration: 120,
            indefinite: false,
            percentage: 130,
            smbIsOff: true,
            isPreset: false,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // When
        try await storage.storeOverride(override: testOverride)

        // Then verify stored entries
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Test Override"),
            key: "date",
            ascending: false
        ) as? [OverrideStored]

        #expect(storedEntries?.isEmpty == false, "Should have stored entries")
        #expect(storedEntries?.count == 1, "Should have exactly one entry")
        let storedOverride = storedEntries?.first
        #expect(storedOverride?.name == "Test Override", "Name should match")
        #expect(storedOverride?.percentage == 130, "Percentage should match")
        #expect(storedOverride?.target?.decimalValue == 110, "Target should match")
        #expect(storedOverride?.isPreset == false, "isPreset should match")
    }

    @Test("Store and retrieve override preset") func testStoreAndRetrieveOverridePreset() async throws {
        // Given
        let testPreset = Override(
            name: "Test Preset",
            enabled: false,
            date: Date(),
            duration: 0,
            indefinite: true,
            percentage: 120,
            smbIsOff: true,
            isPreset: true,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // When
        try await storage.storeOverride(override: testPreset)
        let presetIDs = try await storage.fetchForOverridePresets()

        // Then
        #expect(!presetIDs.isEmpty, "Should have stored preset")

        let storedPresets = try await testContext.perform {
            try presetIDs.map { try testContext.existingObject(with: $0) as! OverrideStored }
        }

        #expect(storedPresets.count >= 1, "Should have at least one preset")
        let storedPreset = storedPresets.first { $0.name == "Test Preset" }
        #expect(storedPreset != nil, "Should find the test preset")
        #expect(storedPreset?.isPreset == true, "Should be marked as preset")
        #expect(storedPreset?.indefinite == true, "Should be indefinite")
        #expect(storedPreset?.percentage == 120, "Percentage should match")
    }

    @Test("Delete override preset") func testDeleteOverridePreset() async throws {
        // Given
        let testPreset = Override(
            name: "Delete Test",
            enabled: false,
            date: Date(),
            duration: 0,
            indefinite: true,
            percentage: 120,
            smbIsOff: true,
            isPreset: true,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // Store the preset
        try await storage.storeOverride(override: testPreset)

        // Get the stored preset's ObjectID
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Delete Test"),
            key: "date",
            ascending: false
        ) as? [OverrideStored]

        guard let objectID = storedEntries?.first?.objectID else {
            throw TestError("Failed to get stored preset's ObjectID")
        }

        // When
        await storage.deleteOverridePreset(objectID)

        // Then verify deletion
        let remainingEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "name == %@", "Delete Test"),
            key: "date",
            ascending: false
        ) as? [OverrideStored]

        #expect(remainingEntries?.isEmpty == true, "Should have no entries after deletion")
    }

    @Test("Get overrides not yet uploaded to Nightscout") func testGetOverridesNotYetUploadedToNightscout() async throws {
        // Given
        let testOverride = Override(
            name: "NS Test",
            enabled: true, // getOverridesNotYetUploadedToNightscout() fetches only active overrides
            date: Date(),
            duration: 90,
            indefinite: false,
            percentage: 120,
            smbIsOff: true,
            isPreset: true,
            id: UUID().uuidString,
            overrideTarget: true,
            target: 110,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 1,
            end: 2,
            smbMinutes: 100,
            uamMinutes: 120
        )

        // When
        try await storage.storeOverride(override: testOverride)

        let notUploadedOverrides = try await storage.getOverridesNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedOverrides.isEmpty == true, "Should have overrides not uploaded to NS")
        #expect(notUploadedOverrides[0].notes == "NS Test", "Override name should match")
        #expect(notUploadedOverrides[0].duration == 90, "Duration should match")
        #expect(notUploadedOverrides[0].eventType == .nsExercise, "Event type should be exercise")
    }
}
