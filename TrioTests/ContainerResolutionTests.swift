import CoreData
import Swinject
import Testing
@testable import Trio

@Suite("Container Resolution Tests", .serialized) struct ContainerResolutionTests {
    private static func makeResolver() async throws -> Resolver {
        let coreDataStack = try await CoreDataStack.createForTests()
        return Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: coreDataStack.newTaskContext())
        ]).resolver
    }

    @Test("Every eagerly loaded service resolves") func testEagerServiceGraph() async throws {
        let resolver = try await Self.makeResolver()

        // Mirrors TrioApp.loadServices() so a missing registration fails here, not at app launch
        #expect(resolver.resolve(AppearanceManager.self) != nil)
        #expect(resolver.resolve(DeviceDataManager.self) != nil)
        #expect(resolver.resolve(APSManager.self) != nil)
        #expect(resolver.resolve(FetchGlucoseManager.self) != nil)
        #expect(resolver.resolve(FetchTreatmentsManager.self) != nil)
        #expect(resolver.resolve(CalendarManager.self) != nil)
        #expect(resolver.resolve(UserNotificationsManager.self) != nil)
        #expect(resolver.resolve(WatchManager.self) != nil)
        #expect(resolver.resolve(ContactImageManager.self) != nil)
        #expect(resolver.resolve(HealthKitManager.self) != nil)
        #expect(resolver.resolve(GarminManager.self) != nil)
        #expect(resolver.resolve(BluetoothStateManager.self) != nil)
        #expect(resolver.resolve(PluginManager.self) != nil)
        #expect(resolver.resolve(AlertPermissionsChecker.self) != nil)
        #expect(resolver.resolve(IOBService.self) != nil)
        #expect(resolver.resolve(GlucoseAlertCoordinator.self) != nil)
        #expect(resolver.resolve(NotLoopingMonitor.self) != nil)
        #expect(resolver.resolve(TrioAlertManager.self) != nil)
        if #available(iOS 16.2, *) {
            #expect(resolver.resolve(LiveActivityManager.self) != nil)
        }
    }

    @Test("Container-scoped singletons resolve and stay identical") func testConvertedSingletons() async throws {
        let resolver = try await Self.makeResolver()

        #expect(resolver.resolve(TrioRemoteControl.self) != nil)
        #expect(resolver.resolve(TelemetryClient.self) != nil)
        #expect(resolver.resolve(TelemetryAttestor.self) != nil)

        // Container scope must return the same instance on every resolve
        #expect(resolver.resolve(TrioRemoteControl.self) === resolver.resolve(TrioRemoteControl.self))
        #expect(resolver.resolve(TelemetryClient.self) === resolver.resolve(TelemetryClient.self))
    }
}
