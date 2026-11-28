@testable import DanaKit
import Foundation
import LoopKit
import Testing
@testable import Trio

@Suite("Therapy Profile Manager Tests", .serialized) struct TherapyProfileManagerTests {
    private let sport = TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)], sens: [(0, 70)], target: [(0, 120, 120)])
    private let defaultBasal = [TherapyProfileFixtures.decimal(0.85), 1]

    @Test("Before any change, Default is active and holds the stored therapy settings") func firstRun() async throws {
        let context = try await TherapyProfileTestContext.make()
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.manager.profiles().map(\.name) == ["Default"])
        #expect(context.manager.activeProfile().hasSameValues(as: TherapyProfileFixtures.profile("Default")))
        #expect(context.liveSettings == context.manager.activeProfile())
    }

    @Test("Before therapy settings are stored, Default is active with the bundled defaults") func emptyStore() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.manager.activeProfile() == TrioTherapyProfile.bundledDefaults)
        #expect(context.liveSettings == TrioTherapyProfile.bundledDefaults)
        #expect(context.profileStorage.storedLiveSettings == nil)
        #expect(try await context.profileStorage.fetchProfiles() == .empty)

        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let stored = try await context.profileStorage.fetchProfiles()
        #expect(stored.activeProfileName == "Default")
        #expect(stored.activeProfileValues == TrioTherapyProfile.bundledDefaults)
    }

    @Test("Onboarding's save stores the settings as they are, without the pump") func storeLiveSettings() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        context.recorder.pumpSuspended = true
        let settings = TherapyProfileFixtures.profile("Any", basal: [(0, 0.7)], carbratio: [(0, 8)])

        try await context.manager.storeLiveSettings(settings)

        #expect(context.manager.activeProfile() == settings.renamed("Default"))
        #expect(context.liveSettings == settings.renamed("Default"))
        #expect(try await context.relaunched().liveSettings == settings.renamed("Default"))
        #expect(context.recorder.events == [.liveChanged, .profilesChanged])
    }

    @Test("Saving a new profile stores it and leaves the pump and the therapy settings in use alone") func create() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)

        let stored = try await context.profileStorage.fetchProfiles()
        #expect(stored.activeProfileName == "Default")
        #expect(stored.inactiveProfiles == [sport])
        #expect(context.manager.profiles().map(\.name) == ["Default", "Sport"])
        #expect(context.recorder.events == [.profilesChanged])
        #expect(context.liveBasal == defaultBasal)
    }

    @Test("A duplicate or reserved name is refused") func createDuplicate() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        await #expect(throws: TherapyProfileError.alreadyExists("sport")) {
            try await context.manager.save(sport.renamed("sport"), originalName: nil, baseFingerprint: nil)
        }
        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.save(sport.renamed("default"), originalName: nil, baseFingerprint: nil)
        }
    }

    @Test("A switch writes the pump before it stores the profiles, then refreshes the determination") func switchOrder() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        context.recorder.events = []

        try await context.manager.activate("Sport", expectedFingerprint: sport.fingerprint(units: .mgdL))

        #expect(context.recorder.events == [
            .pump([0.5], liveBasalAtCall: defaultBasal),
            .liveChanged,
            .profilesChanged,
            .recompute
        ])
        #expect(context.manager.activeProfileName == "Sport")
        #expect(context.liveBasal == [0.5])
        #expect(context.liveSettings.insulinSensitivities.sensitivities.map(\.sensitivity) == [70])
        #expect(context.liveSettings.bgTargets.targets.map(\.low) == [120])
        #expect(try context.relaunched().liveSettings == sport)

        let stored = try await context.profileStorage.fetchProfiles()
        #expect(stored.activeProfileName == "Sport")
        #expect(stored.inactiveProfiles.map(\.name) == ["Default"])
        #expect(stored.inactiveProfiles.first?.hasSameValues(as: TherapyProfileFixtures.profile("Default")) == true)
    }

    @Test("A switch is kept until it is uploaded, a rename adds none") func switchKeptForUpload() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        try await context.manager.save(sport.renamed("Sports"), originalName: "Sport", baseFingerprint: nil)

        #expect(try await context.profileStorage.profileSwitchesNotYetUploaded().map(\.name) == ["Sport"])
        #expect(try await context.profileStorage.profilesNotYetUploaded())
    }

    @Test("Activating the active profile changes nothing") func switchToActive() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.activate("default", expectedFingerprint: nil)
        #expect(context.recorder.events.isEmpty)
    }

    @Test("A pump failure leaves the stored profiles unchanged") func switchPumpFailure() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let before = try await context.profileStorage.fetchProfiles()
        context.recorder.events = []
        context.recorder.pumpError = PumpFailure()

        await #expect(throws: TherapyProfileError.pumpSyncFailed("pump unreachable")) {
            try await context.manager.activate("Sport", expectedFingerprint: nil)
        }
        #expect(try await context.profileStorage.fetchProfiles() == before)
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.recorder.events == [.pump([0.5], liveBasalAtCall: defaultBasal)])
    }

    @Test("A suspended pump refuses changes that write basal rates, other edits still save") func suspendedPump() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let before = try await context.profileStorage.fetchProfiles()
        context.recorder.events = []
        context.recorder.pumpSuspended = true

        await #expect(throws: TherapyProfileError.pumpSuspended) {
            try await context.manager.activate("Sport", expectedFingerprint: nil)
        }
        let base = context.manager.activeProfile()
        let updated = base.replacing(basalProfile: TherapyProfileFixtures.profile("x", basal: [(0, 0.7)]).basalProfileEntries)
        await #expect(throws: TherapyProfileError.pumpSuspended) {
            try await context.manager.save(updated, originalName: "Default", baseFingerprint: nil)
        }
        #expect(try await context.profileStorage.fetchProfiles() == before)
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.recorder.pumpWrites == 0)

        try await context.manager.save(
            sport.renamed("Sport").replacing(basalProfile: updated.basalProfileEntries),
            originalName: "Sport",
            baseFingerprint: nil
        )
        #expect(context.manager.profile(named: "Sport")?.basal == updated.basal)
        #expect(context.recorder.pumpWrites == 0)
    }

    @Test("A failed Core Data save changes nothing and restores the pump") func switchStoreFailure() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let before = try await context.profileStorage.fetchProfiles()
        context.recorder.events = []
        context.profileStorage.failsToStore = true

        await #expect(throws: TherapyProfileError.storageFailed) {
            try await context.manager.activate("Sport", expectedFingerprint: nil)
        }
        #expect(try await context.profileStorage.fetchProfiles() == before)
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.liveBasal == defaultBasal)
        #expect(context.recorder.events == [
            .pump([0.5], liveBasalAtCall: defaultBasal),
            .pump(defaultBasal, liveBasalAtCall: defaultBasal)
        ])
    }

    @Test("A failed pump restore after a failed save says which basal rates the pump may hold") func switchRestoreFailure() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let before = try await context.profileStorage.fetchProfiles()
        context.profileStorage.failsToStore = true
        context.recorder.pumpResults = [nil, PumpFailure()]

        await #expect(throws: TherapyProfileError.pumpRestoreFailed(pumpProfile: "Sport", liveProfile: "Default")) {
            try await context.manager.activate("Sport", expectedFingerprint: nil)
        }
        #expect(try await context.profileStorage.fetchProfiles() == before)
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.recorder.pumpWrites == 2)
    }

    @Test("A switch that stops before its save leaves the previous profile in use on the next launch") func switchInterrupted(
    ) async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let before = try await context.profileStorage.fetchProfiles()
        context.profileStorage.beforeStore = { throw CancellationError() }
        _ = try? await context.manager.activate("Sport", expectedFingerprint: nil)

        let relaunched = try context.relaunched()
        #expect(relaunched.manager.activeProfileName == "Default")
        #expect(relaunched.liveBasal == defaultBasal)
        #expect(try await relaunched.profileStorage.fetchProfiles() == before)
        #expect(try await relaunched.profileStorage.profileSwitchesNotYetUploaded().isEmpty)
    }

    @Test("A failed store leaves the profiles in memory as they were") func failedStoreKeepsMemory() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        #expect(context.manager.profiles().map(\.name) == ["Default", "Sport"])
        #expect(context.manager.activeProfileName == "Sport")

        context.profileStorage.failsToStore = true
        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.save(TherapyProfileFixtures.profile("Night"), originalName: nil, baseFingerprint: nil)
        }
        #expect(context.manager.profiles().map(\.name) == ["Default", "Sport"])
        #expect(context.liveSettings == sport)
    }

    @Test("The getters read the same as a fresh load after every change") func matchesFreshLoad() async throws {
        let context = try await TherapyProfileTestContext.make()
        func expectFreshLoad() async throws {
            let relaunched = try context.relaunched()
            #expect(context.manager.activeProfileName == relaunched.manager.activeProfileName)
            #expect(context.manager.profiles() == relaunched.manager.profiles())
            #expect(context.liveSettings == relaunched.liveSettings)
            #expect(context.manager.scheduledSwitches() == relaunched.manager.scheduledSwitches())
        }

        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await expectFreshLoad()
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        try await expectFreshLoad()
        try await context.manager.saveScheduledSwitches(
            [ScheduledProfileSwitch(profileName: "Default", weekday: 2, time: 21600)],
            baseFingerprint: nil
        )
        try await expectFreshLoad()
        try await context.manager.save(sport.renamed("Run"), originalName: "Sport", baseFingerprint: nil)
        try await expectFreshLoad()
        try await context.manager.save(TherapyProfileFixtures.profile("Night"), originalName: nil, baseFingerprint: nil)
        try await context.manager.delete("Night", expectedFingerprint: nil)
        try await expectFreshLoad()
        context.profileStorage.failsToStore = true
        _ = try? await context.manager.activate("Default", expectedFingerprint: nil)
        context.profileStorage.failsToStore = false
        try await expectFreshLoad()
    }

    @Test("After a launch the getters read the stored profiles on first use") func loadedOnFirstUse() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        let stored = try await context.profileStorage.fetchProfiles()

        let relaunched = try context.relaunched()
        #expect(relaunched.manager.activeProfileName == "Sport")
        #expect(relaunched.manager.activeProfile() == sport)
        #expect(try relaunched.profileStorage.requireLiveSettings() == sport)
        #expect(try await relaunched.profileStorage.fetchProfiles() == stored)
        #expect(relaunched.recorder.events.isEmpty)
    }

    @Test("While the profiles cannot be read, oref gets no settings and changes are refused") func unreadable() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.activate("Sport", expectedFingerprint: nil)

        let relaunched = try context.relaunched()
        relaunched.profileStorage.failsToFetch = true
        #expect(throws: TherapyProfileError.storageFailed) { try relaunched.profileStorage.requireLiveSettings() }
        #expect(relaunched.manager.activeProfileName == "Default")
        #expect(relaunched.manager.activeProfile() == TrioTherapyProfile.bundledDefaults)
        await #expect(throws: TherapyProfileError.storageFailed) {
            try await relaunched.manager.activate("Default", expectedFingerprint: nil)
        }
        #expect(relaunched.recorder.events.isEmpty)

        relaunched.profileStorage.failsToFetch = false
        #expect(relaunched.manager.activeProfileName == "Sport")
        #expect(try relaunched.profileStorage.requireLiveSettings() == sport)
    }

    @Test("Blocked profiles give oref no settings and refuse every change until the next launch") func blocked() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let before = try await context.profileStorage.fetchProfiles()
        let blockedBy = TherapyProfileStorageError.legacyImportFailed("unreadable file")
        context.profileStorage.blockProfiles(blockedBy)

        #expect(throws: blockedBy) { try context.profileStorage.requireLiveSettings() }
        #expect(context.profileStorage.storedLiveSettings == nil)
        await #expect(throws: TherapyProfileError.storageFailed) {
            try await context.manager.activate("Sport", expectedFingerprint: nil)
        }
        let base = TherapyProfileFixtures.profile("Default")
        await #expect(throws: TherapyProfileError.storageFailed) {
            try await context.manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL)
            ) { $0.withSensitivity(55) }
        }
        await #expect(throws: blockedBy) { try await context.profileStorage.storeProfiles(before) }
        #expect(context.recorder.pumpWrites == 0)
        #expect(try await context.profileStorage.fetchProfiles() == before)
        #expect(try context.relaunched().profileStorage.requireLiveSettings() == base)
    }

    @Test("Invalid profiles are refused before the pump is touched") func switchInvalid() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(
            TherapyProfileFixtures.profile("High", basal: [(0, 2)]),
            originalName: nil,
            baseFingerprint: nil
        )
        context.recorder.basalLimits = TherapyBasalLimits(
            supportedRates: context.recorder.basalLimits.supportedRates,
            maxBasal: 1.5
        )
        context.recorder.events = []

        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.activate("High", expectedFingerprint: nil)
        }
        #expect(context.recorder.events.isEmpty)
        #expect(context.liveBasal == defaultBasal)
    }

    @Test("A fingerprint mismatch is a conflict") func switchConflict() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        context.recorder.events = []
        await #expect(throws: TherapyProfileError.conflict("Sport")) {
            try await context.manager.activate("Sport", expectedFingerprint: "ffffffffffffffff")
        }
        #expect(context.recorder.events.isEmpty)
    }

    @Test("Edits of the therapy settings in use stay with the profile across switches") func liveEditsKept() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let base = context.manager.activeProfile()
        let carbRatios = TherapyProfileFixtures.profile("x", carbratio: [(0, 7)]).carbRatios
        try await context.manager.saveLiveSettings(
            expectedActiveName: base.name,
            expectedFingerprint: base.fingerprint(units: .mgdL)
        ) { $0.replacing(carbRatios: carbRatios) }

        try await context.manager.activate("Sport", expectedFingerprint: nil)
        #expect(context.manager.profile(named: "Default")?.carbRatio.map(\.value) == [7])
        try await context.manager.activate("default", expectedFingerprint: nil)
        #expect(context.liveSettings.carbRatios.schedule.map(\.ratio) == [7])
        #expect(context.manager.activeProfileName == "Default")
    }

    @Test("Saving the active profile writes the pump first, then stores the values") func saveActive() async throws {
        let context = try await TherapyProfileTestContext.make()
        let base = context.manager.activeProfile()
        let updated = base.replacing(basalProfile: TherapyProfileFixtures.profile("x", basal: [(0, 0.7)]).basalProfileEntries)

        try await context.manager.save(updated, originalName: "default", baseFingerprint: base.fingerprint(units: .mmolL))

        #expect(context.recorder.events == [
            .pump([TherapyProfileFixtures.decimal(0.7)], liveBasalAtCall: defaultBasal),
            .liveChanged,
            .profilesChanged,
            .recompute
        ])
        #expect(context.liveBasal == [TherapyProfileFixtures.decimal(0.7)])
    }

    @Test("Saving the active profile with an unchanged basal schedule skips the pump") func saveActiveSameBasal() async throws {
        let context = try await TherapyProfileTestContext.make()
        let base = context.manager.activeProfile()
        let updated = base.withSensitivity(55)

        try await context.manager.save(updated, originalName: "Default", baseFingerprint: base.fingerprint(units: .mgdL))

        #expect(context.recorder.pumpWrites == 0)
        #expect(context.liveSettings.insulinSensitivities.sensitivities.map(\.sensitivity) == [55])
    }

    @Test("Saving a profile unchanged changes nothing") func saveUnchanged() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let base = context.manager.activeProfile()
        let eventsBefore = context.recorder.events.count

        try await context.manager.save(sport, originalName: "Sport", baseFingerprint: sport.fingerprint(units: .mgdL))
        try await context.manager.save(base, originalName: "Default", baseFingerprint: base.fingerprint(units: .mgdL))

        #expect(context.recorder.events.count == eventsBefore)
    }

    @Test("Updates need a matching base fingerprint") func saveConflict() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        await #expect(throws: TherapyProfileError.conflict("Sport")) {
            try await context.manager.save(sport, originalName: "Sport", baseFingerprint: "0123456789abcdef")
        }
        await #expect(throws: TherapyProfileError.notFound("Nope")) {
            try await context.manager.save(sport, originalName: "Nope", baseFingerprint: nil)
        }
    }

    @Test("Rename keeps the values and refuses taken names and Default") func rename() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.save(sport.renamed("School"), originalName: nil, baseFingerprint: nil)
        let fingerprint = sport.fingerprint(units: .mgdL)

        await #expect(throws: TherapyProfileError.alreadyExists("School")) {
            try await context.manager.save(sport.renamed("School"), originalName: "Sport", baseFingerprint: fingerprint)
        }
        try await context.manager.save(sport.renamed("Running"), originalName: "Sport", baseFingerprint: fingerprint)
        #expect(context.manager.profiles().map(\.name) == ["Default", "Running", "School"])
        #expect(context.manager.profile(named: "Running")?.hasSameValues(as: sport) == true)

        let base = context.manager.activeProfile()
        await #expect(throws: TherapyProfileError.cannotRenameDefault) {
            try await context.manager.save(base.renamed("Main"), originalName: "Default", baseFingerprint: nil)
        }
    }

    @Test("A rename keeps working after the pump's limits changed, a value change does not") func renameAfterLimitsChanged() async throws {
        let context = try await TherapyProfileTestContext.make()
        let fine = TherapyProfileFixtures.profile("Fine", basal: [(0, 0.07)])
        context.recorder.basalLimits = TherapyBasalLimits(supportedRates: [TherapyProfileFixtures.decimal(0.07), 1], maxBasal: 3)
        try await context.manager.save(fine, originalName: nil, baseFingerprint: nil)
        context.recorder.basalLimits = TherapyBasalLimits(supportedRates: [1], maxBasal: 3)
        let fingerprint = fine.fingerprint(units: .mgdL)

        try await context.manager.save(fine.renamed("Finer"), originalName: "Fine", baseFingerprint: fingerprint)
        #expect(context.manager.profile(named: "Finer")?.hasSameValues(as: fine) == true)

        let changed = fine.renamed("Finer").withSensitivity(55)
        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.save(changed, originalName: "Finer", baseFingerprint: fingerprint)
        }
        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.activate("Finer", expectedFingerprint: nil)
        }
    }

    @Test("Renaming the active profile keeps it active and leaves the pump alone") func renameActive() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        context.recorder.events = []

        try await context.manager.save(
            sport.renamed("Run"),
            originalName: "Sport",
            baseFingerprint: sport.fingerprint(units: .mgdL)
        )

        #expect(context.manager.activeProfileName == "Run")
        #expect(context.recorder.events == [.profilesChanged])
    }

    @Test("A live settings save runs when the active profile is unchanged") func liveSave() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        let base = context.manager.activeProfile()
        let carbRatios = TherapyProfileFixtures.profile("x", carbratio: [(0, 7)]).carbRatios
        context.recorder.events = []

        let saved = try await context.manager.saveLiveSettings(
            expectedActiveName: base.name,
            expectedFingerprint: base.fingerprint(units: .mgdL)
        ) { $0.replacing(carbRatios: carbRatios) }
        #expect(saved.name == "Sport")
        #expect(saved.carbRatio.map(\.value) == [7])
        #expect(saved.basal == base.basal)
        #expect(context.liveSettings == saved)
        #expect(try await context.profileStorage.fetchProfiles().activeProfileValues?.carbRatio.map(\.value) == [7])
        // No pump write and no determination refresh for an editor's save.
        #expect(context.recorder.events == [.liveChanged, .profilesChanged])

        try await context.manager.activate("Default", expectedFingerprint: nil)
        #expect(context.manager.profile(named: "Sport")?.carbRatio.map(\.value) == [7])
        #expect(context.manager.activeProfile().carbRatio.map(\.value) == [10])
    }

    @Test("A live settings save leaves the profiles to upload") func liveSaveUpload() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.profileStorage.markProfilesUploaded(context.profileStorage.fetchProfiles())
        #expect(try await !context.profileStorage.profilesNotYetUploaded())
        let base = context.manager.activeProfile()
        let carbRatios = TherapyProfileFixtures.profile("x", carbratio: [(0, 7)]).carbRatios

        try await context.manager.saveLiveSettings(
            expectedActiveName: base.name,
            expectedFingerprint: base.fingerprint(units: .mgdL)
        ) { $0.replacing(carbRatios: carbRatios) }

        #expect(try await context.profileStorage.profilesNotYetUploaded())
    }

    @Test("A live settings save is refused after a switch") func liveSaveAfterSwitch() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let base = context.manager.activeProfile()
        try await context.manager.activate("Sport", expectedFingerprint: nil)

        let wrote = LockedFlag()
        await #expect(throws: TherapyProfileError.activeProfileChanged(expected: "Default", current: "Sport")) {
            try await context.manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL)
            ) { wrote.set()
                return $0 }
        }
        #expect(!wrote.value)
    }

    @Test("A live settings save is refused after the active profile's values changed") func liveSaveAfterEdit() async throws {
        let context = try await TherapyProfileTestContext.make()
        let base = context.manager.activeProfile()
        let edited = base.withSensitivity(55)
        try await context.manager.save(edited, originalName: "Default", baseFingerprint: base.fingerprint(units: .mgdL))

        let wrote = LockedFlag()
        await #expect(throws: TherapyProfileError.activeProfileChanged(expected: "Default", current: "Default")) {
            try await context.manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL)
            ) { wrote.set()
                return $0 }
        }
        #expect(!wrote.value)
    }

    @Test("A live settings save waits for a switch in flight, then is refused") func liveSaveDuringSwitch() async throws {
        let context = try await TherapyProfileTestContext.make()
        let manager = context.manager
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let base = manager.activeProfile()

        let gate = AsyncGate()
        context.recorder.pumpGate = { await gate.wait() }
        let switching = Task { try await manager.activate("Sport", expectedFingerprint: nil) }
        while context.recorder.pumpWrites == 0 {
            await Task.yield()
        }

        let wrote = LockedFlag()
        let editing = Task {
            try await manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL)
            ) { wrote.set()
                return $0 }
        }
        for _ in 0 ..< 50 { await Task.yield() }
        #expect(!wrote.value)

        await gate.open()
        _ = try await switching.value
        await #expect(throws: TherapyProfileError.activeProfileChanged(expected: "Default", current: "Sport")) {
            try await editing.value
        }
        #expect(!wrote.value)
        #expect(manager.activeProfile().hasSameValues(as: sport))
    }

    @Test("Delete refuses the active profile and Default") func delete() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        await #expect(throws: TherapyProfileError.cannotDeleteDefault) {
            try await context.manager.delete("Default", expectedFingerprint: nil)
        }
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        await #expect(throws: TherapyProfileError.cannotDeleteActive) {
            try await context.manager.delete("Sport", expectedFingerprint: nil)
        }
        try await context.manager.activate("Default", expectedFingerprint: nil)
        await #expect(throws: TherapyProfileError.conflict("Sport")) {
            try await context.manager.delete("Sport", expectedFingerprint: "aaaaaaaaaaaaaaaa")
        }
        try await context.manager.delete("Sport", expectedFingerprint: sport.fingerprint(units: .mgdL))
        #expect(context.manager.profiles().map(\.name) == ["Default"])
        #expect(try await context.profileStorage.fetchProfiles().inactiveProfiles.isEmpty)
    }

    @Test("Concurrent changes run one at a time") func serialized() async throws {
        let context = try await TherapyProfileTestContext.make()
        let manager = context.manager
        let sport = self.sport
        await withTaskGroup(of: Void.self) { group in
            for name in ["Sport", "Two", "Three"] {
                group.addTask {
                    _ = try? await manager.save(sport.renamed(name), originalName: nil, baseFingerprint: nil)
                }
            }
        }
        #expect(Set(manager.profiles().map(\.name)) == ["Default", "Sport", "Two", "Three"])
    }

    @Test("Up to the profile limit, unicode names are stored, listed Default first, and can be activated") func manyProfiles() async throws {
        let context = try await TherapyProfileTestContext.make()
        let fullDay = (0 ..< 48).map { ($0 * 1800, (Double($0 + 1) * 5).rounded() / 100) }
        let names = (1 ..< TherapyProfileLimits.maxProfiles).map { "Profil \($0) åäö 🏃" }
        for name in names {
            try await context.manager.save(
                TherapyProfileFixtures.profile(name, basal: fullDay),
                originalName: nil,
                baseFingerprint: nil
            )
        }
        #expect(context.manager.profiles().map(\.name) == ["Default"] + names)
        await #expect(throws: TherapyProfileError.tooManyProfiles) {
            try await context.manager.save(TherapyProfileFixtures.profile("One more"), originalName: nil, baseFingerprint: nil)
        }
        try await context.manager.activate(names[names.count - 1], expectedFingerprint: nil)
        #expect(context.manager.activeProfileName == names[names.count - 1])
        #expect(context.liveBasal.count == 48)
    }

    @Test("A live basal save is refused while the pump is suspended, other live edits still save") func liveSaveSuspended() async throws {
        let context = try await TherapyProfileTestContext.make()
        let base = context.manager.activeProfile()
        context.recorder.pumpSuspended = true
        let before = try await context.profileStorage.fetchProfiles()
        let basal = TherapyProfileFixtures.profile("x", basal: [(0, 0.7)]).basalProfileEntries

        await #expect(throws: TherapyProfileError.pumpSuspended) {
            try await context.manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL),
                writesBasalSchedule: true
            ) { $0.replacing(basalProfile: basal) }
        }
        #expect(try await context.profileStorage.fetchProfiles() == before)
        #expect(context.liveBasal == defaultBasal)
        #expect(context.recorder.pumpWrites == 0)

        try await context.manager.saveLiveSettings(
            expectedActiveName: base.name,
            expectedFingerprint: base.fingerprint(units: .mgdL)
        ) { $0.withSensitivity(55) }
        #expect(context.liveSettings.sensitivity.map(\.value) == [55])
        #expect(context.recorder.pumpWrites == 0)
    }

    @Test("A live basal save writes the pump first, then stores the schedule") func liveBasalSave() async throws {
        let context = try await TherapyProfileTestContext.make()
        let base = context.manager.activeProfile()
        let basal = TherapyProfileFixtures.profile("x", basal: [(0, 0.7)]).basalProfileEntries

        try await context.manager.saveLiveSettings(
            expectedActiveName: base.name,
            expectedFingerprint: base.fingerprint(units: .mgdL),
            writesBasalSchedule: true
        ) { $0.replacing(basalProfile: basal) }

        #expect(context.recorder.events == [
            .pump([TherapyProfileFixtures.decimal(0.7)], liveBasalAtCall: defaultBasal),
            .liveChanged,
            .profilesChanged
        ])
        #expect(context.liveBasal == [TherapyProfileFixtures.decimal(0.7)])
        #expect(try context.relaunched().liveBasal == [TherapyProfileFixtures.decimal(0.7)])
    }

    @Test("A live basal save the pump refuses stores nothing") func liveBasalSavePumpFailure() async throws {
        let context = try await TherapyProfileTestContext.make()
        let base = context.manager.activeProfile()
        let before = try await context.profileStorage.fetchProfiles()
        let basal = TherapyProfileFixtures.profile("x", basal: [(0, 0.7)]).basalProfileEntries
        context.recorder.pumpError = PumpFailure()

        await #expect(throws: TherapyProfileError.pumpSyncFailed("pump unreachable")) {
            try await context.manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL),
                writesBasalSchedule: true
            ) { $0.replacing(basalProfile: basal) }
        }
        #expect(try await context.profileStorage.fetchProfiles() == before)
        #expect(context.liveBasal == defaultBasal)
    }

    @Test(
        "A live save that cannot be stored changes nothing and puts the basal schedule back on the pump"
    ) func liveSaveStoreFailure() async throws {
        let context = try await TherapyProfileTestContext.make()
        let base = context.manager.activeProfile()
        let before = try await context.profileStorage.fetchProfiles()
        let carbRatios = TherapyProfileFixtures.profile("x", carbratio: [(0, 7)]).carbRatios
        let basal = TherapyProfileFixtures.profile("x", basal: [(0, 0.7)]).basalProfileEntries
        context.profileStorage.failsToStore = true

        await #expect(throws: TherapyProfileError.storageFailed) {
            try await context.manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL)
            ) { $0.replacing(carbRatios: carbRatios) }
        }
        #expect(context.manager.activeProfile() == base)
        #expect(context.recorder.events.isEmpty)

        await #expect(throws: TherapyProfileError.storageFailed) {
            try await context.manager.saveLiveSettings(
                expectedActiveName: base.name,
                expectedFingerprint: base.fingerprint(units: .mgdL),
                writesBasalSchedule: true
            ) { $0.replacing(basalProfile: basal) }
        }
        #expect(context.recorder.events == [
            .pump([TherapyProfileFixtures.decimal(0.7)], liveBasalAtCall: defaultBasal),
            .pump(defaultBasal, liveBasalAtCall: defaultBasal)
        ])
        #expect(context.liveSettings == base)
        #expect(try await context.profileStorage.fetchProfiles() == before)

        context.profileStorage.failsToStore = false
        try await context.manager.saveLiveSettings(
            expectedActiveName: base.name,
            expectedFingerprint: base.fingerprint(units: .mgdL)
        ) { $0.replacing(carbRatios: carbRatios) }
        #expect(try await context.profileStorage.fetchProfiles().activeProfileValues?.carbRatio.map(\.value) == [7])
    }

    @Test("Dana rates stored with binary noise equal the same rates sent as exact decimals") func danaRatesKeepValues() async throws {
        let noisyRates = DanaKitPumpManager.onboardingSupportedBasalRates.map { Decimal($0) }
        let editorRate = try #require(noisyRates.first { $0 != $0.rounded(scale: 3) })
        let context = try await TherapyProfileTestContext.make(
            live: TherapyProfileFixtures.profile("Default").replacing(
                basalProfile: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: editorRate)]
            )
        )
        let live = context.manager.activeProfile()
        let exactRate = try #require(Decimal(string: String(format: "%.2f", Double(editorRate))))
        #expect(live.basal.map(\.value) == [exactRate])

        let remote = TrioTherapyProfile(
            name: "Default",
            basal: [TherapyScheduleEntry(seconds: 0, value: exactRate)],
            carbRatio: live.carbRatio,
            sensitivity: live.sensitivity,
            target: live.target
        )
        context.recorder.pumpSuspended = true
        try await context.manager.save(remote, originalName: "Default", baseFingerprint: live.fingerprint(units: .mgdL))
        #expect(context.recorder.pumpWrites == 0)
    }
}

@Suite("Basal Editor Rate Tests") struct BasalEditorRateTests {
    @Test("Every Dana rate is sent to the pump as the pump's own value") func danaScheduleValues() throws {
        let supported = DanaKitPumpManager.onboardingSupportedBasalRates
        func sent(_ rate: Decimal) -> Double {
            DanaKitPumpManager.scheduleValue(for: rate, supportedRates: supported)
        }
        for hundredths in 1 ... 300 {
            let rate = try #require(Decimal(string: String(format: "%.2f", Double(hundredths) / 100)))
            #expect(sent(rate) == Double(hundredths) / 100)
            #expect(sent(Decimal(Double(hundredths) / 100)) == Double(hundredths) / 100)
        }
        #expect(sent(5) == 5)
    }

    @Test("A Dana profile with 0.07 U/h reaches the pump as 7 hundredths, as DanaKit sends its own rates") func danaPacket() throws {
        let supported = DanaKitPumpManager.onboardingSupportedBasalRates
        func hundredths(_ rates: [Double]) throws -> [UInt16] {
            let items = rates.enumerated()
                .map { RepeatingScheduleValue(startTime: TimeInterval($0.offset * 3600), value: $0.element) }
            let packet = DanaBasalSetProfileRate(options: PacketBasalSetProfileRate(
                profileNumber: 0,
                profileBasalRate: DanaKitPumpManagerState.convertBasal(items)
            ))
            let data = try packet.generate()
            return (0 ..< 24).map { UInt16(data[1 + $0 * 2]) | UInt16(data[2 + $0 * 2]) << 8 }
        }
        let school = try #require(Decimal(string: "0.07"))
        #expect(try hundredths([DanaKitPumpManager.scheduleValue(for: school, supportedRates: supported)]).first == 7)

        for start in stride(from: 1, through: 300, by: 24) {
            let range = start ... min(start + 23, 300)
            let exact = try range.map { try #require(Decimal(string: String(format: "%.2f", Double($0) / 100))) }
            let sent = try hundredths(exact.map { DanaKitPumpManager.scheduleValue(for: $0, supportedRates: supported) })
            let own = try hundredths(range.map { Double($0) / 100 })
            #expect(sent.prefix(range.count) == own.prefix(range.count))
        }
    }

    private let danaRates = BasalProfileEditor.Provider.editorRates(DanaKitPumpManager.onboardingSupportedBasalRates)
    private let timeValues = stride(from: 0.0, to: 86400.0, by: 1800.0).map { $0 }

    private func rows(_ entries: [BasalProfileEntry], rates: [Decimal]) -> ([BasalProfileEditor.Item], Bool) {
        BasalProfileEditor.StateModel.items(for: entries, rateValues: rates, timeValues: timeValues)
    }

    @Test("Every Dana rate opens as itself, whether it reads as an exact or a noisy decimal") func everyDanaRate() throws {
        for hundredths in 1 ... 300 {
            let exact = try #require(Decimal(string: String(format: "%.2f", Double(hundredths) / 100)))
            for rate in [exact, Decimal(Double(hundredths) / 100)] {
                let (items, unsupported) = rows([BasalProfileEntry(start: "00:00:00", minutes: 0, rate: rate)], rates: danaRates)
                #expect(!unsupported)
                #expect(danaRates[items[0].rateIndex] == exact)
            }
        }
    }

    @Test("A Dana profile with 0.07 U/h shows 0.07 and saves 0.07") func danaProfileRoundTrip() throws {
        let rate = try #require(Decimal(string: "0.07"))
        let profile = TrioTherapyProfile(
            name: "School",
            basal: [TherapyScheduleEntry(seconds: 0, value: rate), TherapyScheduleEntry(seconds: 3600, value: 0.46)],
            carbRatio: [TherapyScheduleEntry(seconds: 0, value: 10)],
            sensitivity: [TherapyScheduleEntry(seconds: 0, value: 50)],
            target: [TherapyTargetEntry(seconds: 0, low: 100, high: 100)]
        )
        let (items, unsupported) = rows(profile.basalProfileEntries, rates: danaRates)
        #expect(!unsupported)
        let shown = items.map { danaRates[$0.rateIndex] }
        #expect(shown.map { $0.rounded(scale: 3) } == profile.basal.map(\.value))
        #expect(shown[0] == rate)

        let saved = zip(items, shown).map { item, rate in
            let seconds = Int(timeValues[item.timeIndex])
            return BasalProfileEntry(start: TrioTherapyProfile.startString(seconds: seconds), minutes: seconds / 60, rate: rate)
        }
        #expect(profile.replacing(basalProfile: saved) == profile)
    }

    @Test("A rate the pump does not support is flagged and shown as the nearest rate") func unsupportedRate() {
        let omnipodRates = BasalProfileEditor.Provider.editorRates((0 ... 600).map { Double($0) / 20 })
        let supported = rows([BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.85)], rates: omnipodRates)
        #expect(!supported.1)
        #expect(supported.0.map { Double(omnipodRates[$0.rateIndex]) } == [0.85])

        for (rate, shown) in [(Decimal(string: "0.72"), 0.7), (Decimal(40), 30)] {
            let (items, unsupported) = rows(
                [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: rate ?? 0)],
                rates: omnipodRates
            )
            #expect(unsupported)
            #expect(items.map { Double(omnipodRates[$0.rateIndex]) } == [shown])
        }
    }
}
