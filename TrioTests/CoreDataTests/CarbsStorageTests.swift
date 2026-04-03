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

    @Test(
        "Store carb entry with fat/protein creates capped, spaced FPU entries (defaults: adjustment=0.5, delay=60m)"
    ) func testStoreFatProteinCarbEntryCreatesFPUEntries() async throws {
        let fpuID = UUID().uuidString
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Defaults:
        // adjustment = 0.5, delay = 60
        //
        // fat=50g -> 450 kcal
        // protein=100g -> 400 kcal
        // kcal total = 850
        // (kcal/10) = 85
        // 85 * 0.5 = 42.5
        // Int(42.5) = 42 equivalents -> two FPU entries: 21g each
        let mealEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: baseDate,
            actualDate: baseDate,
            carbs: 30,
            fat: 50,
            protein: 100,
            note: "FPU deterministic default split test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: fpuID
        )

        try await storage.storeCarbs([mealEntry], areFetchedFromRemote: false)

        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "fpuID == %@", fpuID),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]

        guard let storedEntries else {
            throw TestError("Failed to fetch entries for fpuID")
        }

        #expect(!storedEntries.isEmpty, "Should have stored entries")

        let originalCarbEntry = storedEntries.first(where: { $0.isFPU == false })
        #expect(originalCarbEntry != nil, "Should have one non-FPU original entry")
        #expect(originalCarbEntry?.carbs == 30, "Original carbs should match")
        #expect(originalCarbEntry?.fat == 50, "Original fat should match")
        #expect(originalCarbEntry?.protein == 100, "Original protein should match")

        let fpuEntries = storedEntries.filter { $0.isFPU == true }
        #expect(fpuEntries.count == 2, "Expected exactly one FPU entry under default settings")
        #expect(Int(fpuEntries[0].carbs) == 21, "Expected 20g carb equivalents under default settings")

        for fpuEntry in fpuEntries {
            #expect(fpuEntry.fat == 0, "FPU fat must be 0")
            #expect(fpuEntry.protein == 0, "FPU protein must be 0")
            #expect(fpuEntry.carbs >= 10, "FPU carbs must be >= 10g")
            #expect(fpuEntry.carbs <= 33, "FPU carbs must be <= 33g")
            #expect(Double(fpuEntry.carbs).truncatingRemainder(dividingBy: 1) == 0, "FPU carbs must be whole grams")
        }

        let scheduledTotal = fpuEntries.reduce(0) { partialResult, fpuEntry in
            partialResult + Int(fpuEntry.carbs)
        }
        #expect(scheduledTotal <= 99, "Scheduled FPU carbs must be capped at 99g")

        // Timing: stable assertions
        // - first FPU entry must be at least +60m after the *input* timestamp (createdAt/actualDate),
        //   but storage may choose a different internal baseDate, so don't assert exact equality.
        let fpuDates = fpuEntries.compactMap(\.date).sorted()
        #expect(fpuDates.count == 2, "FPU entry should have a date")

        let firstFpuDate = fpuDates[0]
        #expect(
            firstFpuDate >= baseDate.addingTimeInterval(60 * 60),
            "First FPU entry should not be scheduled earlier than +60 minutes after the input timestamp"
        )

        #expect(
            storedEntries.allSatisfy { $0.fpuID?.uuidString == fpuID },
            "All entries should share the same fpuID"
        )
    }

    @Test(
        "Store very large fat/protein meal caps FPU equivalents at 99g and splits into 3×33g (defaults: adjustment=0.5, delay=60m)"
    ) func testStoreVeryLargeFatProteinMealCapsAndSplits() async throws {
        let fpuID = UUID().uuidString
        let baseDate = Date(timeIntervalSince1970: 1_700_001_000)

        // Defaults:
        // adjustment = 0.5, delay = 60
        //
        // fat=200g -> 1800 kcal
        // protein=200g -> 800 kcal
        // kcal total = 2600
        // (kcal/10) = 260
        // 260 * 0.5 = 130
        // Int(130) = 130 -> capped to 99 -> split into [33, 33, 33]
        let heftyMealEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: baseDate,
            actualDate: baseDate,
            carbs: 30,
            fat: 200,
            protein: 200,
            note: "Hefty BBQ meal - cap test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: fpuID
        )

        try await storage.storeCarbs([heftyMealEntry], areFetchedFromRemote: false)

        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "fpuID == %@", fpuID),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]

        guard let storedEntries else {
            throw TestError("Failed to fetch entries for fpuID")
        }

        #expect(!storedEntries.isEmpty, "Should have stored entries")

        let originalCarbEntry = storedEntries.first(where: { $0.isFPU == false })
        #expect(originalCarbEntry != nil, "Should have one non-FPU original entry")
        #expect(originalCarbEntry?.carbs == 30, "Original carbs should match")
        #expect(originalCarbEntry?.fat == 200, "Original fat should match")
        #expect(originalCarbEntry?.protein == 200, "Original protein should match")

        let fpuEntries = storedEntries.filter { $0.isFPU == true }
        #expect(fpuEntries.count == 3, "Capped large meal should create exactly 3 FPU entries")

        let fpuGrams = fpuEntries.map { Int($0.carbs) }
        #expect(fpuGrams == [33, 33, 33], "Expected capped split to be [33, 33, 33]")

        let scheduledTotal = fpuEntries.reduce(0) { partialResult, fpuEntry in
            partialResult + Int(fpuEntry.carbs)
        }
        #expect(scheduledTotal == 99, "Total scheduled FPU grams should be exactly 99g after cap")

        for fpuEntry in fpuEntries {
            #expect(fpuEntry.fat == 0, "FPU entry fat must be 0")
            #expect(fpuEntry.protein == 0, "FPU entry protein must be 0")
            #expect(fpuEntry.carbs >= 10, "FPU entry carbs must be >= 10g")
            #expect(fpuEntry.carbs <= 33, "FPU entry carbs must be <= 33g")
            #expect(Double(fpuEntry.carbs).truncatingRemainder(dividingBy: 1) == 0, "FPU carbs must be whole grams")
        }

        // Timing: stable assertions
        let fpuDates = fpuEntries.compactMap(\.date).sorted()
        #expect(fpuDates.count == 3, "All FPU entries should have a date")

        let firstFpuDate = fpuDates[0]
        #expect(
            firstFpuDate >= baseDate.addingTimeInterval(60 * 60),
            "First FPU entry should not be scheduled earlier than +60 minutes after the input timestamp"
        )

        for index in 1 ..< fpuDates.count {
            let spacingSeconds = fpuDates[index].timeIntervalSince(fpuDates[index - 1])
            #expect(Int(spacingSeconds) == 30 * 60, "FPU entries should be spaced +30 minutes apart")
        }

        #expect(
            storedEntries.allSatisfy { $0.fpuID?.uuidString == fpuID },
            "All entries should share the same fpuID"
        )
    }

    @Test(
        "Store small fat/protein meal drops FPU equivalents when total would be <10g (defaults: adjustment=0.5, delay=60m)"
    ) func testStoreSmallFatProteinMealDropsFPUBelowMinimum() async throws {
        let fpuID = UUID().uuidString
        let baseDate = Date(timeIntervalSince1970: 1_700_002_000)

        // Defaults:
        // adjustment = 0.5
        //
        // fat=2g -> 18 kcal
        // protein=2g -> 8 kcal
        // kcal total = 26
        // (kcal/10) = 2.6
        // 2.6 * 0.5 = 1.3
        // Int(1.3) = 1 (<10) -> should be dropped (no FPU entries)
        let smallMealEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: baseDate,
            actualDate: baseDate,
            carbs: 30,
            fat: 2,
            protein: 2,
            note: "Tiny macros - min threshold test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: fpuID
        )

        try await storage.storeCarbs([smallMealEntry], areFetchedFromRemote: false)

        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "fpuID == %@", fpuID),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]

        guard let storedEntries else {
            throw TestError("Failed to fetch entries for fpuID")
        }

        #expect(!storedEntries.isEmpty, "Should have stored at least the original entry")

        let originalCarbEntry = storedEntries.first(where: { $0.isFPU == false })
        #expect(originalCarbEntry != nil, "Should have one non-FPU original entry")
        #expect(originalCarbEntry?.carbs == 30, "Original carbs should match")
        #expect(originalCarbEntry?.fat == 2, "Original fat should match")
        #expect(originalCarbEntry?.protein == 2, "Original protein should match")

        let fpuEntries = storedEntries.filter { $0.isFPU == true }
        #expect(fpuEntries.isEmpty == true, "No FPU entries should be created when equivalents are <10g")

        #expect(
            storedEntries.allSatisfy { $0.fpuID?.uuidString == fpuID },
            "All entries should share the same fpuID"
        )
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
}
