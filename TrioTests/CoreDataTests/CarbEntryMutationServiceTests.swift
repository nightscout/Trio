import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject
import Testing

@testable import Trio

@Suite("CarbEntryMutationService Tests", .serialized) struct CarbEntryMutationServiceTests: Injectable {
    @Injected() var storage: CarbsStorage!
    @Injected() var service: CarbEntryMutationService!
    let resolver: Resolver
    private let nightscout = StubNightscoutManager()
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
            TestAssembly(testContext: testContext),
            RemoteServicesStubAssembly(nightscout: nightscout)
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

        let failures = try await service.deleteMeal(rootObjectID: try await rootObjectID(id: meal.id!))

        #expect(failures.isEmpty)
        #expect(try await allRows().isEmpty)
    }

    @Test("Core Data rows are gone before remote deletes run") func testDeleteIsLocalFirst() async throws {
        let meal = makeMeal(carbs: 30, fat: 50, protein: 100)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        let rowCounts = RowCountRecorder()
        nightscout.onDeleteCarbs = { _ in await rowCounts.append((try? await self.allRows().count) ?? -1) }

        _ = try await service.deleteMeal(rootObjectID: try await rootObjectID(id: meal.id!))

        #expect(await rowCounts.counts == [0, 0])
    }

    @Test("Overlapping replacements of one meal store a single replacement") func testConcurrentReplace() async throws {
        let meal = makeMeal(carbs: 30, fat: 0, protein: 0)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        let rootID = try await rootObjectID(id: meal.id!)
        let first = makeMeal(carbs: 20, fat: 0, protein: 0, date: Date().addingTimeInterval(-600))
        let second = makeMeal(carbs: 40, fat: 0, protein: 0, date: Date().addingTimeInterval(-1200))

        async let firstResult = try? service.replaceMeal(rootObjectID: rootID, with: first)
        async let secondResult = try? service.replaceMeal(rootObjectID: rootID, with: second)
        let results = await [firstResult, secondResult]

        #expect(results.compactMap { $0 }.count == 1)
        #expect(try await allRows().count == 1)
    }

    @Test("Overlapping replacements of a meal with carb equivalents store a single family") func testConcurrentReplaceWithFPU(
    ) async throws {
        let meal = makeMeal(carbs: 30, fat: 50, protein: 100)
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)
        let rootID = try await rootObjectID(id: meal.id!)
        let first = makeMeal(carbs: 20, fat: 40, protein: 80, date: Date().addingTimeInterval(-600))
        let second = makeMeal(carbs: 40, fat: 40, protein: 80, date: Date().addingTimeInterval(-1200))

        async let firstResult = try? service.replaceMeal(rootObjectID: rootID, with: first)
        async let secondResult = try? service.replaceMeal(rootObjectID: rootID, with: second)
        let results = await [firstResult, secondResult]

        #expect(results.compactMap { $0 }.count == 1)
        let roots = try await allRows().filter { !$0.isFPU }
        #expect(roots.count == 1)
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

        let (newID, failures) = try await service.replaceMeal(
            rootObjectID: try await rootObjectID(id: meal.id!),
            with: replacement
        )

        #expect(newID.uuidString == replacement.id)
        #expect(failures.isEmpty)

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

private actor RowCountRecorder {
    private(set) var counts: [Int] = []
    func append(_ count: Int) { counts.append(count) }
}

private final class StubNightscoutManager: NightscoutManager {
    var onDeleteCarbs: (String) async -> Void = { _ in }

    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?
    let cgmDisplayState = CurrentValueSubject<CgmDisplayState?, Never>(nil)
    let cgmProgressHighlight = CurrentValueSubject<LoopKit.DeviceLifecycleProgress?, Never>(nil)
    var cgmURL: URL? { nil }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> { Just([]).eraseToAnyPublisher() }
    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> { Just([]).eraseToAnyPublisher() }
    func sourceInfo() -> [String: Any]? { nil }
    func fetchGlucose(since _: Date) async -> [BloodGlucose] { [] }
    func fetchCarbs() async -> [CarbsEntry] { [] }
    func fetchTempTargets() async -> [TempTarget] { [] }
    func deleteCarbs(withID id: String) async -> Bool {
        await onDeleteCarbs(id)
        return true
    }

    func deleteInsulin(withID _: String) async {}
    func deleteGlucose(withID _: String, withDate _: Date) async {}
    func uploadCarbs() async {}
    func uploadOverrides() async {}
    func uploadTempTargets() async {}
    func uploadProfiles() async throws {}
    func uploadNoteTreatment(note _: String) async -> Bool { true }
    func importSettings() async -> ScheduledNightscoutProfile? { nil }
}

private final class StubHealthKitManager: HealthKitManager {
    var hasGrantedFullWritePermissions: Bool { false }
    func hasGlucoseWritePermission() -> Bool { false }
    func requestPermission() async throws -> Bool { false }
    func checkWriteToHealthPermissions(objectTypeToHealthStore _: HKObjectType) -> Bool { false }
    func uploadGlucose() async {}
    func uploadCarbs() async {}
    func uploadInsulin() async {}
    func deleteGlucose(syncID _: String) async {}
    func deleteMealData(byID _: String, sampleType _: HKSampleType) async {}
    func deleteInsulin(syncID _: String) async {}
}

private final class StubTidepoolManager: TidepoolManager {
    func addTidepoolService(service _: Service) {}
    func getTidepoolServiceUI() -> ServiceUI? { nil }
    func getTidepoolPluginHost() -> PluginHost? { nil }
    func uploadCarbs() async {}
    func deleteCarbs(withSyncId _: UUID, carbs _: Decimal, at _: Date, enteredBy _: String) {}
    func uploadInsulin() async {}
    func deleteInsulin(withSyncId _: String, amount _: Decimal, at _: Date) {}
    func uploadGlucose() async {}
    func uploadSettings() async {}
    func forceTidepoolDataUpload() {}
}

/// Keeps meal mutation tests off the Nightscout, Apple Health and Tidepool accounts configured in the host app.
private final class RemoteServicesStubAssembly: Assembly {
    private let nightscout: StubNightscoutManager

    init(nightscout: StubNightscoutManager) {
        self.nightscout = nightscout
    }

    func assemble(container: Container) {
        container.register(NightscoutManager.self) { _ in self.nightscout }.inObjectScope(.container)
        container.register(HealthKitManager.self) { _ in StubHealthKitManager() }.inObjectScope(.container)
        container.register(TidepoolManager.self) { _ in StubTidepoolManager() }.inObjectScope(.container)
    }
}
