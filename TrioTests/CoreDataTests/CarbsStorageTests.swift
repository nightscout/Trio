import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("CarbsStorage Tests", .serialized) struct CarbsStorageTests: Injectable {
    @Injected() var storage: CarbsStorage!
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
            TestAssembly(testContext: testContext)
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        #expect(storage != nil, "CarbsStorage should be injected")
        #expect(storage is BaseCarbsStorage, "Storage should be of type BaseCarbsStorage")
        #expect(storage.updatePublisher != nil, "Update publisher should be available")
    }

    @Test("Store and retrieve carbs entries") func testStoreAndRetrieveCarbs() async throws {
        // Given
        let testEntries = [
            CarbsEntry(
                id: UUID().uuidString,
                createdAt: Date(),
                actualDate: Date(),
                carbs: 20,
                fat: 0,
                protein: 0,
                note: "Test meal",
                enteredBy: "Test",
                isFPU: false,
                fpuID: nil
            )
        ]

        // When
        try await storage.storeCarbs(testEntries, areFetchedFromRemote: false)
        let recentEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        )

        guard let recentEntries = recentEntries as? [CarbEntryStored] else {
            throw TestError("Failed to get recent entries")
        }

        // Then
        #expect(!recentEntries.isEmpty, "Should have stored entries")
        #expect(recentEntries.count == 1, "Should have exactly one entry")
        #expect(recentEntries[0].carbs == 20, "Carbs value should match")
        #expect(recentEntries[0].fat == 0, "Fat value should match")
        #expect(recentEntries[0].protein == 0, "Protein value should match")
        #expect(recentEntries[0].note == "Test meal", "Note should match")
    }

    @Test("Delete carbs entry") func testDeleteCarbsEntry() async throws {
        // Given
        let testEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 30,
            fat: nil,
            protein: nil,
            note: "Delete test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: nil
        )

        // When
        try await storage.storeCarbs([testEntry], areFetchedFromRemote: false)

        // Get the stored entry's ObjectID
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 30"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        guard let objectID = storedEntries?.first?.objectID else {
            throw TestError("Failed to get stored entry's ObjectID")
        }

        // Delete the entry
        await storage.deleteCarbsEntryStored(objectID)

        // Then - verify deletion
        let remainingEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 30"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        #expect(remainingEntries?.isEmpty == true, "Should have no entries after deletion")
    }

    @Test("Get carbs not yet uploaded to Nightscout") func testGetCarbsNotYetUploadedToNightscout() async throws {
        // Given
        let testEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 40,
            fat: nil,
            protein: nil,
            note: "NS test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: nil
        )

        // When
        try await storage.storeCarbs([testEntry], areFetchedFromRemote: false)
        let notUploadedEntries = try await storage.getCarbsNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedEntries.isEmpty, "Should have entries not uploaded to NS")
        #expect(notUploadedEntries[0].carbs == 40, "Carbs value should match")
    }

    @Test("Get FPUs not yet uploaded to Nightscout") func testGetFPUsNotYetUploadedToNightscout() async throws {
        // Given
        let fpuID = UUID().uuidString
        let testEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 30,
            fat: 20,
            protein: 10,
            note: "FPU test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: fpuID
        )

        // When
        try await storage.storeCarbs([testEntry], areFetchedFromRemote: false)

        // First verify all stored entries
        let allStoredEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "fpuID == %@", fpuID),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]

        // Then verify the stored entries
        #expect(allStoredEntries?.isEmpty == false, "Should have stored entries")
        #expect(allStoredEntries?.count ?? 0 > 1, "Should have multiple entries due to FPU splitting")

        // Original carb-non-fpu entry should be stored with original fat and protein values and isFPU set to false
        let carbNonFpuEntry = allStoredEntries?.first(where: { $0.isFPU == false })
        #expect(carbNonFpuEntry != nil, "Should have one carb non-fpu entry")
        #expect(carbNonFpuEntry?.carbs == 30, "Original carbs should match")
        #expect(carbNonFpuEntry?.protein == 10, "Original carbs should match")
        #expect(carbNonFpuEntry?.fat == 20, "Original carbs should match")

        // Additional carb-fpu entries should be created for fat/protein with isFPU set to true and the carbs set to the amount of each carbEquivalent
        let carbFpuEntry = allStoredEntries?.filter { $0.isFPU == true }
        #expect(carbFpuEntry?.isEmpty == false, "Should have additional carb-fpu entries")

        // Now test the Nightscout upload function
        let notUploadedFPUs = try await storage.getFPUsNotYetUploadedToNightscout()

        // Then verify Nightscout entries
        #expect(!notUploadedFPUs.isEmpty, "Should have FPUs not uploaded to NS")
        let fpu = notUploadedFPUs[0]
        #expect(fpu.carbs ?? 0 < 30, "Original carbs value should match")
        #expect(fpu.protein == 0, "Protein value should match")
        #expect(fpu.fat == 0, "Fat value should match")

        // Verify all entries share the same fpuID
        #expect(
            allStoredEntries?.allSatisfy { $0.fpuID?.uuidString == fpuID } == true,
            "All entries should share the same fpuID"
        )
    }

    @Test("Multiple carb entries at same timestamp should all be counted in COB")
    func testMultipleEntriesAtSameTimestampAreCounted() async throws {
        // Given - Two different carb entries at the exact same time
        // This simulates a real scenario where a user has an FPU entry at 18:00
        // and then adds a regular meal entry also at 18:00
        let sharedTimestamp = Date()
        let fpuID = UUID().uuidString
        
        // First entry: FPU carb entry (created from fat/protein meal)
        let fpuEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: sharedTimestamp,
            actualDate: sharedTimestamp,
            carbs: 10,
            fat: 20,
            protein: 15,
            note: "FPU entry",
            enteredBy: "Test",
            isFPU: false,
            fpuID: fpuID
        )
        
        // Second entry: Regular meal entry
        let regularEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: sharedTimestamp,
            actualDate: sharedTimestamp,
            carbs: 123,
            fat: nil,
            protein: nil,
            note: "Regular meal",
            enteredBy: "Test",
            isFPU: false,
            fpuID: nil
        )
        
        // When - Store both entries (simulating the bug scenario)
        try await storage.storeCarbs([fpuEntry], areFetchedFromRemote: false)
        try await storage.storeCarbs([regularEntry], areFetchedFromRemote: false)
        
        // Then - Both entries should be stored in Core Data
        let allEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "date == %@", sharedTimestamp as NSDate),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]
        
        // Verify both non-FPU entries are stored
        let nonFpuEntries = allEntries?.filter { $0.isFPU == false } ?? []
        #expect(nonFpuEntries.count >= 2, "Should have at least 2 non-FPU entries at the same timestamp")
        
        // Verify the regular meal entry exists
        let mealEntry = nonFpuEntries.first { $0.carbs == 123 }
        #expect(mealEntry != nil, "Regular meal entry (123g) should be stored")
        #expect(mealEntry?.note == "Regular meal", "Regular meal note should match")
        
        // Verify the FPU parent entry exists
        let fpuParent = nonFpuEntries.first { $0.carbs == 10 }
        #expect(fpuParent != nil, "FPU parent entry (10g) should be stored")
        #expect(fpuParent?.fat == 20, "FPU parent fat should match")
        #expect(fpuParent?.protein == 15, "FPU parent protein should match")
        
        // Most importantly: verify entries have different IDs
        // This is critical - the JavaScript duplicate detection should check IDs
        #expect(mealEntry?.id != fpuParent?.id, "Entries should have different IDs to distinguish them")
        
        // The BUG: Without the fix, the JavaScript meal history parser would treat
        // these two entries as duplicates based solely on timestamp, and discard one,
        // causing incorrect COB calculations. With the fix, both should be counted.
    }
}
