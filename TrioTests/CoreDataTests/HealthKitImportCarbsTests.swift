import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

/// Tests for ``CarbsStorage/storeCarbsImportedFromHealth(_:)`` — verifies that entries
/// imported from Apple Health are persisted correctly and flagged so they are never
/// re-uploaded back to HealthKit (avoiding a sync loop).
@Suite("HealthKit Import → CarbsStorage Tests", .serialized)
struct HealthKitImportCarbsTests: Injectable {
    @Injected() var storage: CarbsStorage!
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

    // MARK: - isUploadedToHealth flag

    @Test("Entries imported from Health are persisted with isUploadedToHealth = true")
    func testImportedEntriesAreMarkedAsUploadedToHealth() async throws {
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 35,
            fat: 12,
            protein: 18,
            note: nil,
            enteredBy: CarbsEntry.appleHealth,
            isFPU: false,
            fpuID: nil
        )

        try await storage.storeCarbsImportedFromHealth([entry])

        let stored = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 35 AND isFPU == false"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        guard let stored else { throw TestError("Failed to fetch stored entry") }
        #expect(stored.count == 1)
        #expect(stored[0].isUploadedToHealth == true, "Imported entry must be pre-flagged as uploaded to Health")
    }

    @Test("Entries imported from Health do NOT appear in getCarbsNotYetUploadedToHealth")
    func testImportedEntriesExcludedFromHealthUploadQueue() async throws {
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 45,
            fat: nil,
            protein: nil,
            note: nil,
            enteredBy: CarbsEntry.appleHealth,
            isFPU: false,
            fpuID: nil
        )

        try await storage.storeCarbsImportedFromHealth([entry])

        let pending = try await storage.getCarbsNotYetUploadedToHealth()

        // The imported entry must not be enqueued for upload
        let importedInQueue = pending.filter { $0.carbs == 45 && $0.enteredBy == CarbsEntry.appleHealth }
        #expect(importedInQueue.isEmpty, "Imported entries must not be re-uploaded to Health")
    }

    // MARK: - Macro values

    @Test("Carbs, fat and protein values are persisted accurately")
    func testMacroValuesStoredCorrectly() async throws {
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 52,
            fat: 21,
            protein: 37,
            note: nil,
            enteredBy: CarbsEntry.appleHealth,
            isFPU: false,
            fpuID: nil
        )

        try await storage.storeCarbsImportedFromHealth([entry])

        let stored = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 52 AND isFPU == false"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        guard let first = stored?.first else { throw TestError("Entry not found") }
        #expect(first.carbs == 52)
        #expect(first.fat == 21)
        #expect(first.protein == 37)
    }

    @Test("Fat=nil and protein=nil entries are stored with fat=0 and protein=0")
    func testNilMacrosStoredAsZero() async throws {
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 28,
            fat: nil,
            protein: nil,
            note: nil,
            enteredBy: CarbsEntry.appleHealth,
            isFPU: false,
            fpuID: nil
        )

        try await storage.storeCarbsImportedFromHealth([entry])

        let stored = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 28 AND isFPU == false"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        guard let first = stored?.first else { throw TestError("Entry not found") }
        #expect(first.fat == 0)
        #expect(first.protein == 0)
    }

    // MARK: - FPU creation

    @Test("Imported fat+protein entry triggers FPU creation (same as manual entry)")
    func testImportedFatProteinTriggersFPU() async throws {
        let fpuID = UUID().uuidString
        let base = Date(timeIntervalSince1970: 1_700_100_000)

        // fat=50g (450 kcal) + protein=100g (400 kcal) = 850 kcal
        // 850/10 * 0.5 = 42.5 → 42 carb equivalents → 2 FPU entries (21g each)
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: base,
            actualDate: base,
            carbs: 0,
            fat: 50,
            protein: 100,
            note: nil,
            enteredBy: CarbsEntry.appleHealth,
            isFPU: false,
            fpuID: fpuID
        )

        try await storage.storeCarbsImportedFromHealth([entry])

        let allStored = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "fpuID == %@", fpuID),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]

        guard let allStored else { throw TestError("Failed to fetch entries") }

        let fpuEntries = allStored.filter { $0.isFPU == true }
        #expect(fpuEntries.isEmpty == false, "Fat+protein import should create FPU entries")
        #expect(fpuEntries.count == 2, "42 equivalents should split into 2 FPU entries")
    }

    // MARK: - Deduplication

    @Test("Importing the same entry twice does not create duplicate records")
    func testDuplicateImportIsDeduped() async throws {
        let date = Date(timeIntervalSince1970: 1_700_200_000)
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: date,
            actualDate: date,
            carbs: 33,
            fat: nil,
            protein: nil,
            note: nil,
            enteredBy: CarbsEntry.appleHealth,
            isFPU: false,
            fpuID: nil
        )

        try await storage.storeCarbsImportedFromHealth([entry])
        try await storage.storeCarbsImportedFromHealth([entry]) // second import

        let stored = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 33 AND isFPU == false"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        // filterRemoteEntries deduplicates by date, so only one record expected
        #expect(stored?.count == 1, "Duplicate import must be silently ignored")
    }
}
