import CoreData
import Foundation
import Swinject
import Testing

@testable import LoopKit
@testable import Trio

@Suite("PumpHistoryStorage Tests", .serialized) struct PumpHistoryStorageTests: Injectable {
    @Injected() var storage: PumpHistoryStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!
    typealias PumpEvent = PumpEventStored.EventType

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
            TestAssembly(testContext: testContext) // Add our test assembly last to override PumpHistoryStorage
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        // Verify storage exists
        #expect(storage != nil, "PumpHistoryStorage should be injected")

        // Verify it's the correct type
        #expect(
            storage is BasePumpHistoryStorage, "Storage should be of type BasePumpHistoryStorage"
        )

        // Verify we can access the update publisher
        #expect(storage.updatePublisher != nil, "Update publisher should be available")
    }

    @Test("Test read and delete using generic CoreDataStack functions") func testFetchAndDeletePumpEvents() async throws {
        // Given
        let date = Date()

        // Insert mock entry
        let events: [LoopKit.NewPumpEvent] = [
            LoopKit.NewPumpEvent(
                date: date,
                dose: LoopKit.DoseEntry(
                    type: .bolus,
                    startDate: date,
                    value: 0.5,
                    unit: .units,
                    deliveredUnits: nil,
                    description: nil,
                    syncIdentifier: nil,
                    scheduledBasalRate: nil,
                    insulinType: .lyumjev,
                    automatic: false,
                    manuallyEntered: false,
                    isMutable: false
                ),
                raw: Data(),
                title: "Test Bolus for Fetch",
                type: .bolus
            )
        ]

        // Store test event
        try await storage.storePumpEvents(events)

        // When - Fetch events with our generic fetch function
        let fetchedEvents = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: testContext,
            predicate: NSPredicate(
                format: "type == %@ AND timestamp == %@",
                PumpEvent.bolus.rawValue,
                date as NSDate
            ),
            key: "timestamp",
            ascending: false
        )

        guard let fetchedEvents = fetchedEvents as? [PumpEventStored] else { return }

        // Then
        #expect(fetchedEvents.count == 1, "Should have found exactly one event")
        let fetchedEvent = fetchedEvents.first
        #expect(fetchedEvent?.type == PumpEvent.bolus.rawValue, "Should be a bolus event")
        #expect(fetchedEvent?.bolus?.amount as? Decimal == 0.5, "Bolus amount should be 0.5")
        #expect(
            abs(fetchedEvent?.timestamp?.timeIntervalSince(date) ?? 1) < 1,
            "Timestamp should match"
        )

        // When - Delete event
        if let fetchedEvent = fetchedEvent {
            await coreDataStack.deleteObject(identifiedBy: fetchedEvent.objectID)
        }

        // Then - Verify deletion
        let eventsAfterDeletion = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: testContext,
            predicate: NSPredicate(
                format: "type == %@ AND timestamp == %@",
                PumpEvent.bolus.rawValue,
                date as NSDate
            ),
            key: "timestamp",
            ascending: false
        )

        guard let eventsAfterDeletion = eventsAfterDeletion as? [PumpEventStored] else { return }

        #expect(eventsAfterDeletion.isEmpty, "Should have no events after deletion")
    }

    @Test("Test store function in PumpHistoryStorage") func testStorePumpEvents() async throws {
        // Given
        let date = Date()
        let tenMinAgo = date.addingTimeInterval(-10.minutes.timeInterval)
        let halfHourInFuture = date.addingTimeInterval(30.minutes.timeInterval)

        // Get initial entries to compare to final entries later
        let initialEntries = try await testContext.perform {
            try testContext.fetch(PumpEventStored.fetchRequest())
        }

        // Create 2 test events, 1 bolus + 1 temp basal event
        let events: [LoopKit.NewPumpEvent] = [
            // SMB
            LoopKit.NewPumpEvent(
                date: tenMinAgo,
                dose: LoopKit.DoseEntry(
                    type: .bolus,
                    startDate: tenMinAgo,
                    value: 0.4,
                    unit: .units,
                    deliveredUnits: nil,
                    description: nil,
                    syncIdentifier: nil,
                    scheduledBasalRate: nil,
                    insulinType: .lyumjev,
                    automatic: true,
                    manuallyEntered: false,
                    isMutable: false
                ),
                raw: Data(),
                title: "Test Bolus",
                type: .bolus
            ),
            // Temp Basal event
            LoopKit.NewPumpEvent(
                date: date,
                dose: LoopKit.DoseEntry(
                    type: .tempBasal,
                    startDate: date,
                    endDate: halfHourInFuture,
                    value: 1.2,
                    unit: .unitsPerHour,
                    deliveredUnits: nil,
                    description: nil,
                    syncIdentifier: nil,
                    scheduledBasalRate: nil,
                    insulinType: .lyumjev,
                    automatic: true,
                    manuallyEntered: false,
                    isMutable: true
                ),
                raw: Data(),
                title: "Test Temp Basal",
                type: .tempBasal
            )
        ]

        // When
        // Store in our in-memory PumphistoryStorage
        try await storage.storePumpEvents(events)

        // Then
        // Fetch all events after storing
        let finalEntries = try await testContext.perform {
            try testContext.fetch(PumpEventStored.fetchRequest())
        }

        // Verify there were no initial entries
        #expect(initialEntries.isEmpty, "There should be no initial entries")

        // Verify count increased by 2
        #expect(finalEntries.count == initialEntries.count + 2, "Should have added 2 new events")

        // Verify bolus event
        let bolusEvent = finalEntries.first {
            $0.type == PumpEvent.bolus.rawValue &&
                abs($0.timestamp?.timeIntervalSince(tenMinAgo) ?? 1) < 1
        }
        #expect(bolusEvent != nil, "Should have found bolus event")
        #expect(bolusEvent?.bolus?.amount as? Decimal == 0.4, "Bolus amount should be 0.4")
        #expect(bolusEvent?.isUploadedToNS == false, "Should not be uploaded to NS")
        #expect(bolusEvent?.isUploadedToHealth == false, "Should not be uploaded to Health")
        #expect(bolusEvent?.isUploadedToTidepool == false, "Should not be uploaded to Tidepool")
        #expect(bolusEvent?.bolus?.isSMB == true, "Should be a SMB")
        #expect(bolusEvent?.bolus?.isExternal == false, "Should not be external insulin")

        // Verify temp basal event
        let tempBasalEvent = finalEntries.first {
            $0.type == PumpEvent.tempBasal.rawValue &&
                abs($0.timestamp?.timeIntervalSince(date) ?? 1) < 1
        }
        #expect(tempBasalEvent != nil, "Should have found temp basal event")
        #expect(tempBasalEvent?.tempBasal?.rate as? Decimal == 1.2, "Temp basal rate should be 1.2")
        #expect(tempBasalEvent?.tempBasal?.duration == 30, "Temp basal duration should be 30 minutes")
        #expect(tempBasalEvent?.isUploadedToNS == false, "Should not be uploaded to NS")
        #expect(tempBasalEvent?.isUploadedToHealth == false, "Should not be uploaded to Health")
        #expect(bolusEvent?.isUploadedToTidepool == false, "Should not be uploaded to Tidepool")
    }

    @Test("Test store function for manual boluses") func testStorePumpEventsWithManualBoluses() async throws {
        // Given
        let date = Date()

        // Insert mock entry
        let events: [LoopKit.NewPumpEvent] = [
            LoopKit.NewPumpEvent(
                date: date,
                dose: LoopKit.DoseEntry(
                    type: .bolus,
                    startDate: date,
                    value: 4,
                    unit: .units,
                    deliveredUnits: nil,
                    description: nil,
                    syncIdentifier: nil,
                    scheduledBasalRate: nil,
                    insulinType: .lyumjev,
                    automatic: false,
                    manuallyEntered: false,
                    isMutable: false
                ),
                raw: Data(),
                title: "Test Bolus",
                type: .bolus
            )
        ]

        // Store test event and wait for storage to complete the task
        try await storage.storePumpEvents(events)

        // When - Fetch events with our generic fetch function
        let fetchedEvents = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: testContext,
            predicate: NSPredicate(
                format: "type == %@ AND timestamp == %@",
                PumpEvent.bolus.rawValue,
                date as NSDate
            ),
            key: "timestamp",
            ascending: false
        )

        guard let fetchedEvents = fetchedEvents as? [PumpEventStored] else { return }

        // Then
        #expect(fetchedEvents.count == 1, "Should have found exactly one event")
        let fetchedEvent = fetchedEvents.first
        #expect(fetchedEvent?.type == PumpEvent.bolus.rawValue, "Should be a bolus event")
        #expect(fetchedEvent?.bolus?.amount as? Decimal == 4, "Bolus amount should be 4 U")
        #expect(
            abs(fetchedEvent?.timestamp?.timeIntervalSince(date) ?? 1) < 1,
            "Timestamp should match"
        )
        #expect(fetchedEvent?.bolus?.isSMB == false, "Should not be a SMB")
        #expect(fetchedEvent?.bolus?.isExternal == false, "Should not be external Insulin")
        #expect(fetchedEvent?.isUploadedToNS == false, "Should not be uploaded to NS")
        #expect(fetchedEvent?.isUploadedToHealth == false, "Should not be uploaded to Health")
        #expect(fetchedEvent?.isUploadedToTidepool == false, "Should not be uploaded to Tidepool")
    }

    @Test("Test duplicates in PumpHistoryStorage") func testDuplicatePumpEvents() async throws {
        // Given
        let date = Date()
        let twoHoursAgo = date - 2.hours.timeInterval
        let oneMinuteAgo = date - 1.minutes.timeInterval

        // Get initial entries to compare to final entries later
        let initialEntries = try await testContext.perform {
            try testContext.fetch(PumpEventStored.fetchRequest())
        }

        // Create two suspend events and two resume events
        let events: [LoopKit.NewPumpEvent] = [
            LoopKit.NewPumpEvent(
                date: twoHoursAgo,
                dose: nil,
                raw: Data(),
                title: "Test Suspend",
                type: .suspend
            ),
            LoopKit.NewPumpEvent(
                date: twoHoursAgo,
                dose: nil,
                raw: Data(),
                title: "Test Suspend",
                type: .suspend
            ),
            LoopKit.NewPumpEvent(
                date: oneMinuteAgo,
                dose: nil,
                raw: Data(),
                title: "Test Resume",
                type: .resume
            ),
            LoopKit.NewPumpEvent(
                date: oneMinuteAgo,
                dose: nil,
                raw: Data(),
                title: "Test Resume",
                type: .resume
            )
        ]

        // When
        // Store in our in-memory PumphistoryStorage
        try await storage.storePumpEvents(events)

        // Then
        // Fetch all events after storing
        let finalEntriesUnsorted = try await testContext.perform {
            try testContext.fetch(PumpEventStored.fetchRequest())
        }
        let finalEntries = finalEntriesUnsorted.sorted { $0.timestamp! < $1.timestamp! }

        // Verify there were no initial entries
        #expect(initialEntries.isEmpty, "There should be no initial entries")

        // Verify count increased by 2
        #expect(finalEntries.count == initialEntries.count + 2, "Should have added 2 new events")

        #expect(finalEntries.first?.type == PumpEvent.pumpSuspend.rawValue)
        #expect(finalEntries.last?.type == PumpEvent.pumpResume.rawValue)
    }
}
