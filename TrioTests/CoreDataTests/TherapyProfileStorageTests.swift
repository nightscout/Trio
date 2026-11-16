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

    @Test("Nothing is stored before the first save") func emptyStore() async throws {
        #expect(try await storage.fetchProfiles() == StoredTherapyProfiles(activeProfileName: nil, inactiveProfiles: []))
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

        let fetched = try await storage.fetchProfiles()
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
        #expect(try await storage.fetchProfiles().activeProfileValues == live.renamed("Sport"))

        try await storage.storeProfiles(StoredTherapyProfiles(activeProfileName: "Sport", inactiveProfiles: []))
        #expect(try await storage.fetchProfiles().activeProfileValues == nil)
    }

    @Test("Schedules come back in time order") func scheduleOrder() async throws {
        let profile = TherapyProfileFixtures.profile("Order", basal: [(0, 1), (1800, 1.1), (3600, 1.2), (84600, 0.9)])
        try await storage.storeProfiles(StoredTherapyProfiles(activeProfileName: "Default", inactiveProfiles: [profile]))
        #expect(try await storage.fetchProfiles().inactiveProfiles == [profile])
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
        var fetched = try await storage.fetchProfiles()
        #expect(fetched.scheduledSwitches == entries.sortedByWeek)
        #expect(fetched.scheduledSwitchesSettledAt == settledAt)

        try await storage.settleScheduledSwitches(at: settledAt.addingTimeInterval(60))
        #expect(try await storage.fetchProfiles().scheduledSwitchesSettledAt == settledAt.addingTimeInterval(60))

        fetched.scheduledSwitches = [entries[1]]
        try await storage.storeProfiles(fetched)
        #expect(try await storage.fetchProfiles().scheduledSwitches == [entries[1]])
        #expect(try await rowCount(ScheduledProfileSwitchStored.self) == 1)
    }

    @Test("Two profiles with the same name ignoring case are refused and nothing changes") func duplicateNames() async throws {
        let stored = StoredTherapyProfiles(
            activeProfileName: "Default",
            inactiveProfiles: [TherapyProfileFixtures.profile("Sport")]
        )
        try await storage.storeProfiles(stored)

        let duplicates = [
            StoredTherapyProfiles(activeProfileName: "Default", inactiveProfiles: [TherapyProfileFixtures.profile("default")]),
            StoredTherapyProfiles(
                activeProfileName: "Default",
                inactiveProfiles: [TherapyProfileFixtures.profile("Sport"), TherapyProfileFixtures.profile("SPORT")]
            )
        ]
        for profiles in duplicates {
            await #expect(throws: TherapyProfileStorageError.duplicateName) { try await storage.storeProfiles(profiles) }
        }
        #expect(try await storage.fetchProfiles() == stored)
    }

    @Test("Out-of-range weekdays, times and schedule offsets are refused and nothing changes") func outOfRange() async throws {
        let stored = StoredTherapyProfiles(
            activeProfileName: "Default",
            inactiveProfiles: [TherapyProfileFixtures.profile("Sport")],
            scheduledSwitches: [ScheduledProfileSwitch(id: "s", profileName: "Sport", weekday: 2, time: 21600)]
        )
        try await storage.storeProfiles(stored)

        let switches: [(weekday: Int, time: Int, error: String)] = [
            (0, 0, "weekday 0"),
            (8, 0, "weekday 8"),
            (1, 86400, "time 86400"),
            (1, -60, "time -60"),
            (1, 30, "time 30"),
            (1, Int(Int32.max) + 61, "time \(Int(Int32.max) + 61)")
        ]
        for entry in switches {
            var profiles = stored
            profiles.scheduledSwitches = [ScheduledProfileSwitch(profileName: "Sport", weekday: entry.weekday, time: entry.time)]
            await #expect(throws: TherapyProfileStorageError.valueOutOfRange(entry.error)) {
                try await storage.storeProfiles(profiles)
            }
        }
        for offset in [-1800, 86400, Int(Int32.max) + 1] {
            let profile = TherapyProfileFixtures.profile("Sport", basal: [(0, 1), (offset, 1.2)])
            var inactive = stored
            inactive.inactiveProfiles = [profile]
            var active = stored
            active.activeProfileValues = profile
            for profiles in [inactive, active] {
                await #expect(throws: TherapyProfileStorageError.valueOutOfRange("schedule offset \(offset)")) {
                    try await storage.storeProfiles(profiles)
                }
            }
        }
        #expect(try await storage.fetchProfiles() == stored)
    }

    @Test("Values, scheduled switches or a settled instant without an active profile are refused") func noActiveProfile() async throws {
        let refused = [
            StoredTherapyProfiles(
                activeProfileName: nil,
                inactiveProfiles: [],
                scheduledSwitches: [ScheduledProfileSwitch(profileName: "Default", weekday: 2, time: 0)]
            ),
            StoredTherapyProfiles(activeProfileName: nil, inactiveProfiles: [], scheduledSwitchesSettledAt: Date()),
            StoredTherapyProfiles(
                activeProfileName: nil,
                inactiveProfiles: [],
                activeProfileValues: TherapyProfileFixtures.profile("Default")
            )
        ]
        for profiles in refused {
            await #expect(throws: TherapyProfileStorageError.noActiveProfile) { try await storage.storeProfiles(profiles) }
        }
        await #expect(throws: TherapyProfileStorageError.noActiveProfile) {
            try await storage.settleScheduledSwitches(at: Date())
        }
        #expect(try await rowCount(TherapyProfileStored.self) == 0)
        #expect(try await rowCount(ScheduledProfileSwitchStored.self) == 0)
    }
}
