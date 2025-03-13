import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("GlucoseStorage Tests", .serialized) struct GlucoseStorageTests: Injectable {
    @Injected() var storage: GlucoseStorage!
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
        #expect(storage != nil, "GlucoseStorage should be injected")

        // Verify it's the correct type
        #expect(storage is BaseGlucoseStorage, "Storage should be of type BaseGlucoseStorage")
    }

    @Test("Store and retrieve glucose entries") func testStoreAndRetrieveGlucose() async throws {
        // Given
        let testGlucose = [
            BloodGlucose(direction: BloodGlucose.Direction.flat, date: 123, dateString: Date(), glucose: 126)
        ]

        // When
        try await storage.storeGlucose(testGlucose)

        // Then verify stored entries
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "glucose == 126"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored]

        #expect(storedEntries?.isEmpty == false, "Should have stored entries")
        #expect(storedEntries?.count == 1, "Should have exactly one entry")
        #expect(storedEntries?[0].glucose == 126, "Glucose value should match")
        #expect(storedEntries?[0].direction == "Flat", "Direction should match")
    }

    @Test("Delete glucose entry") func testDeleteGlucose() async throws {
        // Given
        let testGlucose = [
            BloodGlucose(direction: BloodGlucose.Direction.flat, date: 123, dateString: Date(), glucose: 140)
        ]
        try await storage.storeGlucose(testGlucose)

        // Get the stored entry's ObjectID
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "glucose == 140"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored]

        guard let objectID = storedEntries?.first?.objectID else {
            throw TestError("Failed to get stored entry's ObjectID")
        }

        #expect(storedEntries.isNotNilNotEmpty == true, "Should have exactly one (test) entry")

        // When
        await storage.deleteGlucose(objectID)

        // Then verify deletion
        let remainingEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "glucose == 140"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored]

        #expect(remainingEntries?.isEmpty == true, "Should have no entries after deletion")
    }

    @Test("Get glucose not yet uploaded to Nightscout") func testGetGlucoseNotYetUploadedToNightscout() async throws {
        // Given
        let testGlucose = [
            BloodGlucose(direction: BloodGlucose.Direction.flat, date: 123, dateString: Date(), glucose: 160)
        ]
        try await storage.storeGlucose(testGlucose)

        // When
        let notUploadedEntries = try await storage.getGlucoseNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedEntries.isEmpty, "Should have entries not uploaded to NS")
        #expect(notUploadedEntries[0].glucose == 160, "Glucose value should match")
    }

    @Test("Get manual glucose not yet uploaded to Nightscout") func testGetManualGlucoseNotYetUploadedToNightscout() async throws {
        // Given
        storage.addManualGlucose(glucose: 180)

        // When
        let notUploadedEntries = try await storage.getManualGlucoseNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedEntries.isEmpty, "Should have manual entries not uploaded to NS")
        let entry = notUploadedEntries[0]
        #expect(entry.glucose == "180", "Glucose value should match")
        #expect(entry.glucoseType == "Manual", "Type should be mbg for manual entries")
        #expect(entry.eventType == .capillaryGlucose, "Type should be capillaryGlucose")
    }

    @Test("Test glucose alarms") func testGlucoseAlarms() async throws {
        // Given
        let lowGlucose = [
            BloodGlucose(direction: BloodGlucose.Direction.flat, date: 123, dateString: Date(), glucose: 55)
        ]
        let highGlucose = [
            BloodGlucose(direction: BloodGlucose.Direction.flat, date: 123, dateString: Date(), glucose: 271)
        ]
        let normalGlucose = [
            BloodGlucose(direction: BloodGlucose.Direction.flat, date: 123, dateString: Date(), glucose: 100)
        ]

        // When - Test low glucose
        try await storage.storeGlucose(lowGlucose)
        var storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "glucose == 55"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored]

        // Then
        #expect(storedEntries?.first?.glucose == 55, "Low glucose value should match")
        #expect(storage.alarm == .low, "Should trigger low glucose alarm") // default low limit is 72 mg/dL

        // When - Test high glucose
        try await storage.storeGlucose(highGlucose)
        storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "glucose == 271"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored]

        // Then
        #expect(storedEntries?.first?.glucose == 271, "High glucose value should match")
        #expect(storage.alarm == .high, "Should trigger high glucose alarm") // default high limit is 270 mg/dL

        // When - Test normal glucose
        try await storage.storeGlucose(normalGlucose)
        storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "glucose == 100"),
            key: "date",
            ascending: false
        ) as? [GlucoseStored]

        // Then
        #expect(storedEntries?.first?.glucose == 100, "Normal glucose value should match")
        #expect(storage.alarm == nil, "Should not trigger any alarm")
    }
}
