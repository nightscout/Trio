import CoreData
import Foundation
import HealthKit
import Swinject
import Testing

@testable import LoopKit
@testable import Trio

@Suite("Pump Status Storage Tests", .serialized) struct PumpStatusStorageTests: Injectable {
    @Injected() var storage: PumpStatusStorage!
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

    private func status(_ basalDeliveryState: PumpManagerStatus.BasalDeliveryState?) -> PumpManagerStatus {
        PumpManagerStatus(
            timeZone: .current,
            device: HKDevice(
                name: "Pump", manufacturer: nil, model: nil, hardwareVersion: nil, firmwareVersion: nil,
                softwareVersion: nil, localIdentifier: nil, udiDeviceIdentifier: nil
            ),
            pumpBatteryChargeRemaining: nil,
            basalDeliveryState: basalDeliveryState,
            bolusState: .noBolus,
            insulinType: nil,
            deliveryIsUncertain: false
        )
    }

    private func tempBasal() -> PumpManagerStatus.BasalDeliveryState {
        .tempBasal(DoseEntry(
            type: .tempBasal,
            startDate: Date(),
            endDate: Date().addingTimeInterval(30 * 60),
            value: 1.2,
            unit: .unitsPerHour
        ))
    }

    /// Stored rows, oldest first. Runs on the storage's context, after the stores it has queued.
    private func storedRows() async -> [(state: String?, date: Date?)] {
        await testContext.perform {
            let request = PumpStatusStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PumpStatusStored.date, ascending: true)]
            let rows = (try? testContext.fetch(request)) ?? []
            return rows.map { ($0.basalDeliveryState, $0.date) }
        }
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        #expect(storage is BasePumpStatusStorage)
    }

    @Test("No stored status returns nil") func testNoStoredStatus() async {
        #expect(await storage.lastPumpStatus() == nil)
    }

    @Test("Temp basals and their transitions are stored as one active status") func testTempBasalsCollapse() async {
        storage.storePumpStatus(status(.active(Date())))
        storage.storePumpStatus(status(.initiatingTempBasal))
        storage.storePumpStatus(status(tempBasal()))
        storage.storePumpStatus(status(.cancelingTempBasal))
        storage.storePumpStatus(status(.active(Date())))

        let rows = await storedRows()
        #expect(rows.map(\.state) == ["active"])
    }

    @Test("A suspend and resume are stored in order") func testSuspendResumeHistory() async {
        let suspendDate = Date()
        storage.storePumpStatus(status(.active(Date())))
        storage.storePumpStatus(status(.suspending))
        storage.storePumpStatus(status(.suspended(suspendDate)))
        storage.storePumpStatus(status(.suspended(suspendDate)))
        storage.storePumpStatus(status(.resuming))
        storage.storePumpStatus(status(.active(Date())))

        let rows = await storedRows()
        #expect(rows.map(\.state) == ["active", "suspending", "suspended", "resuming", "active"])
        let dates = rows.compactMap(\.date)
        #expect(dates.count == rows.count)
        #expect(dates == dates.sorted())
    }

    @Test("Delivery active since the distant past is stored as inactive") func testInactive() async throws {
        storage.storePumpStatus(status(.active(Date())))
        storage.storePumpStatus(status(.active(.distantPast)))

        #expect(await storedRows().map(\.state) == ["active", "inactive"])
        let inactive = try #require(await storage.lastPumpStatus())
        #expect(inactive.suspended)
    }

    @Test("A removed pump is stored as unknown") func testPumpRemoved() async throws {
        storage.storePumpStatus(status(.active(Date())))
        storage.storePumpRemoved()
        storage.storePumpRemoved()

        #expect(await storedRows().map(\.state) == ["active", "unknown"])
        let removed = try #require(await storage.lastPumpStatus())
        #expect(removed.suspended)
    }

    @Test("Statuses older than 90 days are purged, keeping the latest") func testPurge() async throws {
        let old = Date().addingTimeInterval(-91 * 24 * 60 * 60)
        await testContext.perform {
            for (offset, state) in [(-3600.0, "active"), (0.0, "suspended")] {
                let stored = PumpStatusStored(context: testContext)
                stored.date = old.addingTimeInterval(offset)
                stored.basalDeliveryState = state
            }
            try? testContext.save()
        }

        await storage.deleteStatuses(olderThan: 90)
        #expect(await storedRows().map(\.state) == ["suspended"])

        storage.storePumpStatus(status(.active(Date())))
        await storage.deleteStatuses(olderThan: 90)
        #expect(await storedRows().map(\.state) == ["active"])
    }

    @Test("The legacy status file is migrated into a row") func testLegacyMigration() async throws {
        let fileStorage = try #require(resolver.resolve(FileStorage.self))
        let legacyDate = Date().addingTimeInterval(-3600)
        fileStorage.save(
            PumpStatus(status: .suspended, bolusing: false, suspended: true, timestamp: legacyDate),
            as: "monitor/status.json"
        )

        _ = BasePumpStatusStorage(resolver: resolver, contextProvider: { testContext })

        let rows = await storedRows()
        #expect(rows.map(\.state) == ["suspended"])
        let date = try #require(rows.first?.date)
        #expect(abs(date.timeIntervalSince(legacyDate)) < 1)
        #expect(fileStorage.retrieve("monitor/status.json", as: PumpStatus.self) == nil)
    }

    @Test("The last status maps to a pump status") func testLastPumpStatus() async throws {
        storage.storePumpStatus(status(.suspended(Date())))
        let suspended = try #require(await storage.lastPumpStatus())
        #expect(suspended.suspended)
        #expect(suspended.status == .suspended)
        #expect(!suspended.bolusing)
        let suspendedDate = await storedRows().last?.date
        #expect(suspended.timestamp == suspendedDate)

        storage.storePumpStatus(status(.resuming))
        let resuming = try #require(await storage.lastPumpStatus())
        #expect(!resuming.suspended)
        #expect(resuming.status == .normal)

        storage.storePumpStatus(status(nil))
        let unknown = try #require(await storage.lastPumpStatus())
        #expect(unknown.suspended)
        #expect(await storedRows().map(\.state) == ["suspended", "resuming", "unknown"])
    }
}
