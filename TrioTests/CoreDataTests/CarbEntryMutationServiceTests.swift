import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("CarbEntryMutationService Tests", .serialized) struct CarbEntryMutationServiceTests: Injectable {
    @Injected() var storage: CarbsStorage!
    @Injected() var service: CarbEntryMutationService!
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

    private func makeMeal(carbs: Decimal, fat: Decimal, protein: Decimal, date: Date = Date()) -> CarbsEntry {
        CarbsEntry(
            id: UUID().uuidString,
            createdAt: date,
            actualDate: date,
            carbs: carbs,
            fat: fat,
            protein: protein,
            note: "Mutation test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: fat > 0 || protein > 0 ? UUID().uuidString : nil
        )
    }

    private func allRows() async throws -> [CarbEntryStored] {
        let rows = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]
        guard let rows else { throw TestError("Failed to fetch rows") }
        return rows
    }

    private func rootObjectID(id: String) async throws -> NSManagedObjectID {
        let rows = try await allRows()
        guard let root = rows.first(where: { $0.id?.uuidString == id }) else { throw TestError("Root not found") }
        return root.objectID
    }

    @Test("Service resolves") func testServiceResolves() {
        #expect(service is BaseCarbEntryMutationService)
    }

    @Test("Delete removes the root and its carb equivalents") func testDeleteMealRemovesFamily() async throws {
        let meal = makeMeal(carbs: 30, fat: 50, protein: 100)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        #expect(try await allRows().count == 3)

        let report = try await service.deleteMeal(rootObjectID: try await rootObjectID(id: meal.id!))

        #expect(report.failures.isEmpty)
        #expect(try await allRows().isEmpty)
    }

    @Test("Delete leaves other meals untouched") func testDeleteMealKeepsOthers() async throws {
        let meal = makeMeal(carbs: 30, fat: 50, protein: 100)
        let other = makeMeal(carbs: 12, fat: 0, protein: 0, date: Date().addingTimeInterval(-3600))
        try await storage.storeCarbs([other], areFetchedFromRemote: false)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)

        _ = try await service.deleteMeal(rootObjectID: try await rootObjectID(id: meal.id!))

        let rows = try await allRows()
        #expect(rows.count == 1)
        #expect(rows.first?.id?.uuidString == other.id)
    }

    @Test("Delete on a carb equivalent row is rejected") func testDeleteChildThrows() async throws {
        let meal = makeMeal(carbs: 30, fat: 50, protein: 100)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        guard let child = try await allRows().first(where: { $0.isFPU }) else { throw TestError("No child") }

        await #expect(throws: CarbEntryMutationError.notARoot) {
            _ = try await service.deleteMeal(rootObjectID: child.objectID)
        }
        #expect(try await allRows().count == 3)
    }

    @Test("Replace stores the new meal under the replacement id") func testReplaceMeal() async throws {
        let meal = makeMeal(carbs: 30, fat: 50, protein: 100)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        let replacement = makeMeal(carbs: 15, fat: 20, protein: 40)

        let (newID, report) = try await service.replaceMeal(
            rootObjectID: try await rootObjectID(id: meal.id!),
            with: replacement
        )

        #expect(newID.uuidString == replacement.id)
        #expect(report.failures.isEmpty)

        let rows = try await allRows()
        #expect(rows.contains(where: { $0.id?.uuidString == meal.id }) == false, "Old root is gone")
        let newRoot = rows.first(where: { $0.isFPU == false })
        #expect(newRoot?.id == newID)
        #expect(newRoot?.carbs == 15)
        #expect(newRoot?.fpuID?.uuidString == replacement.fpuID)
        #expect(newRoot?.isUploadedToNS == false)
        let children = rows.filter(\.isFPU)
        #expect(!children.isEmpty)
        #expect(children.allSatisfy { $0.fpuID == newRoot?.fpuID })
    }

    @Test("Replace with a carbs-only meal leaves no carb equivalents") func testReplaceMealDropsFPUs() async throws {
        let meal = makeMeal(carbs: 30, fat: 50, protein: 100)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        let replacement = makeMeal(carbs: 45, fat: 0, protein: 0)

        _ = try await service.replaceMeal(rootObjectID: try await rootObjectID(id: meal.id!), with: replacement)

        let rows = try await allRows()
        #expect(rows.count == 1)
        #expect(rows.first?.fpuID == nil)
        #expect(rows.first?.carbs == 45)
    }

    @Test("Replace requires a UUID replacement id") func testReplaceMealRequiresUUID() async throws {
        let meal = makeMeal(carbs: 30, fat: 0, protein: 0)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        let replacement = CarbsEntry(
            id: "not-a-uuid",
            createdAt: Date(),
            actualDate: Date(),
            carbs: 10,
            fat: 0,
            protein: 0,
            note: nil,
            enteredBy: "Test",
            isFPU: false,
            fpuID: nil
        )

        await #expect(throws: CarbEntryMutationError.invalidReplacementID) {
            _ = try await service.replaceMeal(rootObjectID: try await rootObjectID(id: meal.id!), with: replacement)
        }
        #expect(try await allRows().count == 1, "Nothing is deleted when the replacement is invalid")
    }
}
