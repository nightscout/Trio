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
    var mutationStorage: CarbsStorage!

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
        let testStack = coreDataStack!
        mutationStorage = BaseCarbsStorage(resolver: resolver, contextProvider: { testStack.newTaskContext() })
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
        let storedRoots = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "note == %@ AND isFPU == NO", "NS test"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]
        let storedRootID = try #require(storedRoots?.first?.id?.uuidString)
        let notUploadedEntries = try await storage.getCarbsNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedEntries.isEmpty, "Should have entries not uploaded to NS")
        let root = try #require(notUploadedEntries.first(where: { $0.id == storedRootID }))
        #expect(root.id == storedRootID, "Root ID should match its Core Data UUID")
        #expect(root.fpuID == nil, "Carb-only roots should not publish an FPU family ID")
        #expect(root.carbs == 40, "Carbs value should match")
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
        let storedRootID = try #require(carbNonFpuEntry?.id?.uuidString)

        // Additional carb-fpu entries should be created for fat/protein with isFPU set to true and the carbs set to the amount of each carbEquivalent
        let carbFpuEntry = allStoredEntries?.filter { $0.isFPU == true }
        #expect(carbFpuEntry?.isEmpty == false, "Should have additional carb-fpu entries")

        // Now test the Nightscout upload function
        let notUploadedRoots = try await storage.getCarbsNotYetUploadedToNightscout()
        let notUploadedFPUs = try await storage.getFPUsNotYetUploadedToNightscout()

        // Then verify Nightscout entries
        let root = try #require(notUploadedRoots.first(where: { $0.id == storedRootID }))
        #expect(root.id == storedRootID, "Root ID should match its Core Data UUID")
        #expect(root.fpuID == fpuID, "Root should publish its FPU family ID")
        #expect(root.id != root.fpuID, "A family root should have distinct root and FPU IDs")
        #expect(!notUploadedFPUs.isEmpty, "Should have FPUs not uploaded to NS")
        let fpu = notUploadedFPUs[0]
        #expect(fpu.carbs ?? 0 < 30, "Original carbs value should match")
        #expect(fpu.protein == 0, "Protein value should match")
        #expect(fpu.fat == 0, "Fat value should match")
        for treatment in notUploadedFPUs {
            #expect(treatment.id == fpuID, "Generated FPU treatment ID should remain the family ID")
            #expect(treatment.fpuID == fpuID, "Generated FPU treatment should publish the family ID")
            #expect(treatment.id == treatment.fpuID, "Generated FPU treatment IDs should identify children")
        }

        let encodedFPU = try JSONCoding.encoder.encode([fpu])
        let encodedTreatments = try #require(JSONSerialization.jsonObject(with: encodedFPU) as? [[String: Any]])
        let encodedJSON = try #require(encodedTreatments.first)
        #expect(encodedJSON["fpuID"] as? String == fpuID, "Nightscout JSON should encode the exact fpuID key")

        // Verify all entries share the same fpuID
        #expect(
            allStoredEntries?.allSatisfy { $0.fpuID?.uuidString == fpuID } == true,
            "All entries should share the same fpuID"
        )
    }

    @Test(
        "Remote meal command payload and response metadata use the correlated contract"
    ) func testRemoteMealMutationContract() throws {
        let commandID = UUID()
        let mealID = UUID()
        let editJSON = """
        {
          "user": "LoopFollow",
          "command_type": "edit_meal",
          "timestamp": 1800000000,
          "command_id": "\(commandID.uuidString)",
          "meal_id": "\(mealID.uuidString)",
          "expected_carbs": 30,
          "expected_fat": 10,
          "expected_protein": 5,
          "expected_meal_time": 1799996400,
          "carbs": 25,
          "fat": 12,
          "protein": 6,
          "scheduled_time": 1799996700
        }
        """

        let edit = try JSONDecoder().decode(CommandPayload.self, from: Data(editJSON.utf8))
        #expect(edit.commandType == .editMeal)
        #expect(edit.commandID == commandID.uuidString)
        #expect(edit.mealID == mealID.uuidString)
        #expect(edit.expectedCarbs == 30)
        #expect(edit.expectedFat == 10)
        #expect(edit.expectedProtein == 5)
        #expect(edit.expectedMealTime == 1_799_996_400)
        #expect(edit.carbs == 25)
        #expect(edit.scheduledTime == 1_799_996_700)

        let deleteJSON = """
        {
          "user": "LoopFollow",
          "command_type": "delete_meal",
          "timestamp": 1800000000,
          "command_id": "\(UUID().uuidString)",
          "meal_id": "\(mealID.uuidString)",
          "expected_carbs": 30,
          "expected_fat": 10,
          "expected_protein": 5,
          "expected_meal_time": 1799996400
        }
        """

        let delete = try JSONDecoder().decode(CommandPayload.self, from: Data(deleteJSON.utf8))
        #expect(delete.commandType == .deleteMeal)
        #expect(delete.carbs == nil)
        #expect(delete.scheduledTime == nil)

        let response = RemoteNotificationResponseManager.NotificationPayload(
            aps: .init(alert: .init(title: "Command Successful", body: "Meal updated")),
            commandStatus: "success",
            commandType: TrioRemoteControl.CommandType.editMeal.rawValue,
            timestamp: 1_800_000_000,
            commandID: commandID.uuidString,
            mealID: mealID.uuidString,
            result: .updated,
            syncStatus: .requested
        )
        let responseData = try JSONEncoder().encode(response)
        let responseJSON = try #require(JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let aps = try #require(responseJSON["aps"] as? [String: Any])
        #expect(responseJSON["command_id"] as? String == commandID.uuidString)
        #expect(responseJSON["meal_id"] as? String == mealID.uuidString)
        #expect(responseJSON["result"] as? String == "updated")
        #expect(responseJSON["sync_status"] as? String == "requested")
        #expect(aps["content-available"] as? Int == 1)
    }

    @Test(
        "Remote edit preserves the root identity and replaces its FPU family atomically"
    ) func testRemoteMealEditPreservesRootAndRebuildsFPUFamily() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let originalDate = now.addingTimeInterval(-60 * 60)
        let replacementDate = now.addingTimeInterval(-30 * 60)
        let rootID = UUID()
        let oldFPUID = UUID()
        let oldChildren = [
            MealFPUEntrySnapshot(id: UUID(), date: originalDate.addingTimeInterval(60 * 60), carbs: 12),
            MealFPUEntrySnapshot(id: UUID(), date: originalDate.addingTimeInterval(90 * 60), carbs: 12)
        ]
        try await insertMeal(
            id: rootID,
            date: originalDate,
            carbs: 30,
            fat: 20,
            protein: 10,
            note: "Keep this note",
            fpuID: oldFPUID,
            children: oldChildren
        )

        let expected = MealMutationValues(date: originalDate, carbs: 30, fat: 20, protein: 10)
        let replacement = MealMutationValues(date: replacementDate, carbs: 25, fat: 200, protein: 200)
        let result = try await mutationStorage.mutateMeal(
            id: rootID,
            expected: expected,
            mutation: .edit(replacement),
            now: now
        )

        #expect(result.disposition == .edited)
        #expect(result.before.id == rootID)
        #expect(result.before.fpuID == oldFPUID)
        #expect(Set(result.before.fpuEntries.map(\.id)) == Set(oldChildren.map(\.id)))
        let editedSnapshot = try #require(result.after)
        #expect(editedSnapshot.id == rootID)
        #expect(editedSnapshot.values == replacement)
        #expect(editedSnapshot.note == "Keep this note")
        let replacementFPUID = try #require(editedSnapshot.fpuID)
        #expect(replacementFPUID != oldFPUID)
        #expect(!editedSnapshot.fpuEntries.isEmpty)

        let stored = try await loadMeal(id: rootID)
        #expect(stored.snapshot.id == rootID)
        #expect(stored.snapshot.values == replacement)
        #expect(stored.snapshot.note == "Keep this note")
        #expect(stored.snapshot.fpuID == replacementFPUID)
        #expect(stored.snapshot.fpuEntries == editedSnapshot.fpuEntries)
        let oldChildrenStillExist = try await entriesExist(ids: oldChildren.map(\.id))
        #expect(!oldChildrenStillExist)

        let staleRemoteEntry = CarbsEntry(
            id: rootID.uuidString,
            createdAt: originalDate,
            actualDate: originalDate,
            carbs: 30,
            fat: 20,
            protein: 10,
            note: "Stale Nightscout copy",
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: oldFPUID.uuidString
        )
        try await mutationStorage.storeCarbs([staleRemoteEntry], areFetchedFromRemote: true)
        #expect(!(try await entriesExist(at: originalDate)))

        #expect(try await mutationStorage.getCarbsNotYetUploadedToNightscout().isEmpty)
        #expect(try await mutationStorage.getFPUsNotYetUploadedToNightscout().isEmpty)
        #expect(try await mutationStorage.getCarbsNotYetUploadedToHealth().isEmpty)
        #expect(try await mutationStorage.getCarbsNotYetUploadedToTidepool().isEmpty)

        try await mutationStorage.markMealForUpload(id: rootID)
        let pendingNightscoutRoots = try await mutationStorage.getCarbsNotYetUploadedToNightscout()
        let pendingNightscoutFPUs = try await mutationStorage.getFPUsNotYetUploadedToNightscout()
        let pendingHealth = try await mutationStorage.getCarbsNotYetUploadedToHealth()
        let pendingTidepool = try await mutationStorage.getCarbsNotYetUploadedToTidepool()
        #expect(pendingNightscoutRoots.map(\.id) == [rootID.uuidString])
        let pendingNightscoutRoot = try #require(pendingNightscoutRoots.first)
        #expect(pendingNightscoutRoot.id == rootID.uuidString)
        #expect(pendingNightscoutRoot.fpuID == replacementFPUID.uuidString)
        #expect(pendingNightscoutRoot.id != pendingNightscoutRoot.fpuID)
        #expect(pendingNightscoutFPUs.count == editedSnapshot.fpuEntries.count)
        #expect(pendingNightscoutFPUs.allSatisfy {
            $0.id == replacementFPUID.uuidString &&
                $0.fpuID == replacementFPUID.uuidString &&
                $0.id == $0.fpuID
        })
        #expect(pendingHealth.map(\.id) == [rootID.uuidString])
        #expect(pendingTidepool.map(\.id) == [rootID.uuidString])
    }

    @Test(
        "An already-applied edit succeeds before stale expected-value checking"
    ) func testRemoteMealEditIsIdempotent() async throws {
        let now = Date(timeIntervalSince1970: 1_800_100_000)
        let mealDate = now.addingTimeInterval(-60 * 60)
        let rootID = UUID()
        try await insertMeal(id: rootID, date: mealDate, carbs: 20, fat: 0, protein: 0, note: "Original")

        let staleExpected = MealMutationValues(date: mealDate, carbs: 99, fat: 0, protein: 0)
        let current = MealMutationValues(date: mealDate, carbs: 20, fat: 0, protein: 0)
        let result = try await mutationStorage.mutateMeal(
            id: rootID,
            expected: staleExpected,
            mutation: .edit(current),
            now: now
        )

        #expect(result.disposition == .unchanged)
        #expect(result.before == result.after)
        let stored = try await loadMeal(id: rootID)
        #expect(stored.snapshot.note == "Original")
    }

    @Test(
        "Fat/protein-only roots expose their stable meal ID to Nightscout"
    ) func testRemoteMealMutationFatProteinOnlyRootIsDiscoverable() async throws {
        let now = Date()
        let rootID = UUID()
        try await insertMeal(
            id: rootID,
            date: now.addingTimeInterval(-60),
            carbs: 0,
            fat: 20,
            protein: 10,
            note: "FPU only"
        )

        try await mutationStorage.markMealForUpload(id: rootID)
        let treatments = try await mutationStorage.getCarbsNotYetUploadedToNightscout()
        let treatment = try #require(treatments.first { $0.id == rootID.uuidString })
        #expect(treatment.carbs == 0)
        #expect(treatment.fat == 20)
        #expect(treatment.protein == 10)
    }

    @Test(
        "Remote mutations reject stale values and enforce the closed 12-hour window"
    ) func testRemoteMealMutationSafetyChecks() async throws {
        let now = Date(timeIntervalSince1970: 1_800_200_000)
        let currentID = UUID()
        let currentDate = now.addingTimeInterval(-60 * 60)
        let current = MealMutationValues(date: currentDate, carbs: 15, fat: 0, protein: 0)
        try await insertMeal(id: currentID, date: currentDate, carbs: 15, fat: 0, protein: 0, note: nil)

        do {
            _ = try await mutationStorage.mutateMeal(
                id: currentID,
                expected: MealMutationValues(date: currentDate, carbs: 14, fat: 0, protein: 0),
                mutation: .edit(MealMutationValues(date: currentDate, carbs: 16, fat: 0, protein: 0)),
                now: now
            )
            Issue.record("A stale expected value should not mutate the meal")
        } catch let error as MealMutationError {
            #expect(error == .stale(current: current))
        }

        let boundaryID = UUID()
        let boundaryDate = now.addingTimeInterval(-remoteMealMutationMaximumAge)
        let boundary = MealMutationValues(date: boundaryDate, carbs: 10, fat: 0, protein: 0)
        try await insertMeal(id: boundaryID, date: boundaryDate, carbs: 10, fat: 0, protein: 0, note: nil)
        let boundaryResult = try await mutationStorage.mutateMeal(
            id: boundaryID,
            expected: boundary,
            mutation: .delete,
            now: now
        )
        #expect(boundaryResult.disposition == .deleted)

        let oldID = UUID()
        let oldDate = now.addingTimeInterval(-remoteMealMutationMaximumAge - 0.001)
        let old = MealMutationValues(date: oldDate, carbs: 10, fat: 0, protein: 0)
        try await insertMeal(id: oldID, date: oldDate, carbs: 10, fat: 0, protein: 0, note: nil)
        do {
            _ = try await mutationStorage.mutateMeal(id: oldID, expected: old, mutation: .delete, now: now)
            Issue.record("A meal older than 12 hours should be rejected")
        } catch let error as MealMutationError {
            #expect(error == .outsideEditWindow)
        }

        let futureID = UUID()
        let futureDate = now.addingTimeInterval(0.001)
        let future = MealMutationValues(date: futureDate, carbs: 10, fat: 0, protein: 0)
        try await insertMeal(id: futureID, date: futureDate, carbs: 10, fat: 0, protein: 0, note: nil)
        do {
            _ = try await mutationStorage.mutateMeal(id: futureID, expected: future, mutation: .delete, now: now)
            Issue.record("A future meal should be rejected")
        } catch let error as MealMutationError {
            #expect(error == .outsideEditWindow)
        }

        let replacementID = UUID()
        try await insertMeal(id: replacementID, date: currentDate, carbs: 10, fat: 0, protein: 0, note: nil)
        do {
            _ = try await mutationStorage.mutateMeal(
                id: replacementID,
                expected: MealMutationValues(date: currentDate, carbs: 10, fat: 0, protein: 0),
                mutation: .edit(MealMutationValues(date: futureDate, carbs: 11, fat: 0, protein: 0)),
                now: now
            )
            Issue.record("A replacement time outside the window should be rejected")
        } catch let error as MealMutationError {
            #expect(error == .replacementOutsideEditWindow)
        }
    }

    @Test(
        "Concurrent edits serialize so only one stale expectation can commit"
    ) func testRemoteMealMutationSerializesConcurrentEdits() async throws {
        let now = Date(timeIntervalSince1970: 1_800_250_000)
        let mealDate = now.addingTimeInterval(-60 * 60)
        let rootID = UUID()
        let original = MealMutationValues(date: mealDate, carbs: 20, fat: 0, protein: 0)
        let firstReplacement = MealMutationValues(date: mealDate, carbs: 21, fat: 0, protein: 0)
        let secondReplacement = MealMutationValues(date: mealDate, carbs: 22, fat: 0, protein: 0)
        try await insertMeal(id: rootID, date: mealDate, carbs: 20, fat: 0, protein: 0, note: nil)

        async let first: MealMutationResult? = try? mutationStorage.mutateMeal(
            id: rootID,
            expected: original,
            mutation: .edit(firstReplacement),
            now: now
        )
        async let second: MealMutationResult? = try? mutationStorage.mutateMeal(
            id: rootID,
            expected: original,
            mutation: .edit(secondReplacement),
            now: now
        )
        let (firstResult, secondResult) = await (first, second)
        let results = [firstResult, secondResult].compactMap { $0 }

        #expect(results.count == 1)
        #expect(results.first?.disposition == .edited)
        let stored = try await loadMeal(id: rootID)
        #expect(stored.snapshot.values == firstReplacement || stored.snapshot.values == secondReplacement)
    }

    @Test(
        "Remote delete removes the root and every generated FPU child"
    ) func testRemoteMealDeleteRemovesFamily() async throws {
        let now = Date(timeIntervalSince1970: 1_800_300_000)
        let mealDate = now.addingTimeInterval(-60 * 60)
        let rootID = UUID()
        let fpuID = UUID()
        let children = [
            MealFPUEntrySnapshot(id: UUID(), date: mealDate.addingTimeInterval(60 * 60), carbs: 15),
            MealFPUEntrySnapshot(id: UUID(), date: mealDate.addingTimeInterval(90 * 60), carbs: 15)
        ]
        try await insertMeal(
            id: rootID,
            date: mealDate,
            carbs: 35,
            fat: 30,
            protein: 20,
            note: "Delete family",
            fpuID: fpuID,
            children: children
        )

        let result = try await mutationStorage.mutateMeal(
            id: rootID,
            expected: MealMutationValues(date: mealDate, carbs: 35, fat: 30, protein: 20),
            mutation: .delete,
            now: now
        )

        #expect(result.disposition == .deleted)
        #expect(result.after == nil)
        #expect(Set(result.before.fpuEntries.map(\.id)) == Set(children.map(\.id)))
        let familyStillExists = try await entriesExist(ids: [rootID] + children.map(\.id))
        #expect(!familyStillExists)
    }

    private struct StoredMeal: Sendable {
        let snapshot: MealMutationSnapshot
    }

    private func insertMeal(
        id: UUID,
        date: Date,
        carbs: Double,
        fat: Double,
        protein: Double,
        note: String?,
        fpuID: UUID? = nil,
        children: [MealFPUEntrySnapshot] = []
    ) async throws {
        try await testContext.perform {
            let root = CarbEntryStored(context: self.testContext)
            root.id = id
            root.date = date
            root.carbs = carbs
            root.fat = fat
            root.protein = protein
            root.note = note
            root.fpuID = fpuID
            root.isFPU = false
            root.isUploadedToNS = true
            root.isUploadedToHealth = true
            root.isUploadedToTidepool = true

            for snapshot in children {
                let child = CarbEntryStored(context: self.testContext)
                child.id = snapshot.id
                child.date = snapshot.date
                child.carbs = Double(truncating: NSDecimalNumber(decimal: snapshot.carbs))
                child.fat = 0
                child.protein = 0
                child.fpuID = fpuID
                child.isFPU = true
                child.isUploadedToNS = true
                child.isUploadedToHealth = true
                child.isUploadedToTidepool = true
            }
            try self.testContext.save()
        }
    }

    private func loadMeal(id: UUID) async throws -> StoredMeal {
        try await testContext.perform {
            self.testContext.reset()
            let rootRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            rootRequest.predicate = NSPredicate(format: "id == %@ AND isFPU == NO", id as CVarArg)
            guard let root = try self.testContext.fetch(rootRequest).first,
                  let rootID = root.id,
                  let rootDate = root.date
            else {
                throw TestError("Failed to load stored meal")
            }

            var children: [CarbEntryStored] = []
            if let fpuID = root.fpuID {
                let childRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
                childRequest.predicate = NSPredicate(format: "fpuID == %@ AND isFPU == YES", fpuID as CVarArg)
                childRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
                children = try self.testContext.fetch(childRequest)
            }

            let childSnapshots = try children.map { child in
                guard let childID = child.id, let childDate = child.date else {
                    throw TestError("Failed to load stored FPU entry")
                }
                return MealFPUEntrySnapshot(
                    id: childID,
                    date: childDate,
                    carbs: Decimal(algorithmValue: child.carbs)
                )
            }
            let snapshot = MealMutationSnapshot(
                id: rootID,
                fpuID: root.fpuID,
                values: MealMutationValues(
                    date: rootDate,
                    carbs: Decimal(algorithmValue: root.carbs),
                    fat: Decimal(algorithmValue: root.fat),
                    protein: Decimal(algorithmValue: root.protein)
                ),
                note: root.note,
                fpuEntries: childSnapshots
            )
            return StoredMeal(snapshot: snapshot)
        }
    }

    private func entriesExist(ids: [UUID]) async throws -> Bool {
        try await testContext.perform {
            self.testContext.reset()
            let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)
            request.fetchLimit = 1
            return try self.testContext.count(for: request) > 0
        }
    }

    private func entriesExist(at date: Date) async throws -> Bool {
        try await testContext.perform {
            self.testContext.reset()
            let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            request.predicate = NSPredicate(
                format: "date >= %@ AND date <= %@",
                date.addingTimeInterval(-1) as NSDate,
                date.addingTimeInterval(1) as NSDate
            )
            request.fetchLimit = 1
            return try self.testContext.count(for: request) > 0
        }
    }
}
