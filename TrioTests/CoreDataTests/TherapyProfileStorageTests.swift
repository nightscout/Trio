import CoreData
import Foundation
import Swinject
import Testing
@testable import Trio

@Suite("Therapy Profile Storage Tests", .serialized) struct TherapyProfileStorageTests: Injectable {
    @Injected() var storage: TherapyProfileStorage!
    let resolver: Resolver
    var testContext: NSManagedObjectContext!

    init() async throws {
        let coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()
        resolver = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext)
        ]).resolver
        injectServices(resolver)
    }

    private func rowCount<T: NSManagedObject>(_: T.Type) async throws -> Int {
        let context: NSManagedObjectContext = testContext
        return try await context.perform {
            try context.count(for: NSFetchRequest<T>(entityName: String(describing: T.self)))
        }
    }

    @Test("Nothing is stored before the first save") func emptyStore() throws {
        #expect(try storage.fetchProfiles() == StoredTherapyProfiles(activeProfileName: nil, inactiveProfiles: []))
    }

    @Test("Profiles round-trip, the active one by name only") func roundTrip() async throws {
        let sport = TherapyProfileFixtures.profile(
            "Sport",
            basal: [(0, 0.5), (21600, 0.65), (79200, 0.55)],
            carbratio: [(0, 12), (43200, 9.5)],
            sens: [(0, 70)],
            target: [(0, 120, 130), (28800, 110, 110)]
        )
        let stored = StoredTherapyProfiles(
            activeProfileName: "Sport",
            inactiveProfiles: [TherapyProfileFixtures.profile("Default"), TherapyProfileFixtures.profile("Night")]
        )
        try await storage.storeProfiles(StoredTherapyProfiles(activeProfileName: "Default", inactiveProfiles: [sport]))
        try await storage.storeProfiles(stored)

        let fetched = try storage.fetchProfiles()
        #expect(fetched.activeProfileName == "Sport")
        #expect(fetched.inactiveProfiles.sorted { $0.name < $1.name } == stored.inactiveProfiles)
        #expect(try await rowCount(TherapyProfileStored.self) == 3)
        #expect(try await rowCount(TherapyProfileEntryStored.self) == 2 * 5)
    }

    @Test("The active profile's values at the last store round-trip with its name") func activeProfileValues() async throws {
        let live = TherapyProfileFixtures.profile("x", basal: [(0, 0.5)])
        try await storage.storeProfiles(
            StoredTherapyProfiles(activeProfileName: "Sport", inactiveProfiles: [], activeProfileValues: live)
        )
        #expect(try storage.fetchProfiles().activeProfileValues == live.renamed("Sport"))

        try await storage.storeProfiles(StoredTherapyProfiles(activeProfileName: "Sport", inactiveProfiles: []))
        #expect(try storage.fetchProfiles().activeProfileValues == nil)
    }

    @Test("Schedules come back in time order") func scheduleOrder() async throws {
        let profile = TherapyProfileFixtures.profile("Order", basal: [(0, 1), (1800, 1.1), (3600, 1.2), (84600, 0.9)])
        try await storage.storeProfiles(StoredTherapyProfiles(activeProfileName: "Default", inactiveProfiles: [profile]))
        #expect(try storage.fetchProfiles().inactiveProfiles == [profile])
    }

    @Test("Scheduled switches and the settled instant are stored and replaced with the profiles") func scheduledSwitches() async throws {
        let settledAt = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            ScheduledProfileSwitch(id: "w", profileName: "Weekend", weekday: 7, time: 25200, paused: true),
            ScheduledProfileSwitch(id: "s", profileName: "Default", weekday: 2, time: 21600)
        ]
        try await storage.storeProfiles(StoredTherapyProfiles(
            activeProfileName: "Default",
            inactiveProfiles: [TherapyProfileFixtures.profile("Weekend")],
            scheduledSwitches: entries,
            scheduledSwitchesSettledAt: settledAt
        ))
        var fetched = try storage.fetchProfiles()
        #expect(fetched.scheduledSwitches == entries.sortedByWeek)
        #expect(fetched.scheduledSwitchesSettledAt == settledAt)

        try await storage.settleScheduledSwitches(at: settledAt.addingTimeInterval(60))
        #expect(try storage.fetchProfiles().scheduledSwitchesSettledAt == settledAt.addingTimeInterval(60))

        fetched.scheduledSwitches = [entries[1]]
        try await storage.storeProfiles(fetched)
        #expect(try storage.fetchProfiles().scheduledSwitches == [entries[1]])
        #expect(try await rowCount(ScheduledProfileSwitchStored.self) == 1)
    }
}
