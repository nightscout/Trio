import Foundation
import LoopKit
import Testing
@testable import Trio

@Suite("Therapy Profile Scheduled Switch Tests", .serialized) struct TherapyProfileScheduledSwitchTests {
    private let weekend = TherapyProfileFixtures.profile("Weekend", basal: [(0, 0.5)], sens: [(0, 70)])
    private let calendar = TherapyProfileTestRecorder.calendar

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    /// Weekend starts Saturday 07:00, Default Monday 06:00. Saved on Friday 2026-11-13 12:00 with Default active.
    private func makeContext(paused: Bool = false) async throws -> TherapyProfileTestContext {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(weekend, originalName: nil, baseFingerprint: nil)
        context.recorder.now = date("2026-11-13 12:00")
        try await context.manager.saveScheduledSwitches([
            ScheduledProfileSwitch(id: "w", profileName: "Weekend", weekday: 7, time: 25200, paused: paused),
            ScheduledProfileSwitch(id: "s", profileName: "default", weekday: 2, time: 21600)
        ], baseFingerprint: [ScheduledProfileSwitch]().fingerprint)
        context.recorder.events = []
        return context
    }

    private func settledAt(_ context: TherapyProfileTestContext) throws -> Date? {
        try context.profileStorage.fetchProfiles().scheduledSwitchesSettledAt
    }

    private func issued(_ context: TherapyProfileTestContext, _ name: String) -> [Alert] {
        context.recorder.alerts.issuedAlerts.filter { $0.identifier.alertIdentifier == "scheduledSwitch.\(name)" }
    }

    @Test("Saving the list names Default by its profile name, settles now and arms the next start") func saveList() async throws {
        let context = try await makeContext()
        #expect(context.manager.scheduledSwitches().map(\.profileName) == ["Default", "Weekend"])
        #expect(try settledAt(context) == date("2026-11-13 12:00"))
        let pending = try #require(issued(context, "pending").last)
        #expect(pending.trigger == .delayed(interval: date("2026-11-14 07:30").timeIntervalSince(date("2026-11-13 12:00"))))
        #expect(pending.backgroundContent.body.contains("Weekend"))
    }

    @Test("A list save needs the fingerprint of the current list and existing profiles") func saveListRules() async throws {
        let context = try await makeContext()
        let entries = context.manager.scheduledSwitches()
        await #expect(throws: TherapyProfileError.scheduledSwitchesConflict) {
            try await context.manager.saveScheduledSwitches([], baseFingerprint: [ScheduledProfileSwitch]().fingerprint)
        }
        await #expect(throws: TherapyProfileError.notFound("Nope")) {
            try await context.manager.saveScheduledSwitches(
                entries + [ScheduledProfileSwitch(profileName: "Nope", weekday: 3, time: 0)],
                baseFingerprint: entries.withStoreKeys.fingerprint
            )
        }
        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.saveScheduledSwitches(
                entries + [ScheduledProfileSwitch(profileName: "Default", weekday: 7, time: 25200)],
                baseFingerprint: nil
            )
        }
        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.saveScheduledSwitches(
                (1 ... 15).map { ScheduledProfileSwitch(profileName: "Default", weekday: $0 % 7 + 1, time: $0 * 60) },
                baseFingerprint: nil
            )
        }
        await #expect(throws: TherapyProfileError.self) {
            try await context.manager.saveScheduledSwitches(
                [ScheduledProfileSwitch(profileName: "Default", weekday: 3, time: 30)],
                baseFingerprint: nil
            )
        }
        #expect(context.manager.scheduledSwitches() == entries)
    }

    @Test("A due start switches, settles at its time and refreshes the determination") func dueSwitch() async throws {
        let context = try await makeContext()
        context.recorder.now = date("2026-11-14 07:02")
        await context.manager.runDueScheduledSwitch()

        #expect(context.manager.activeProfileName == "Weekend")
        #expect(context.liveBasal == [0.5])
        #expect(context.recorder.events == [
            .pump([0.5], liveBasalAtCall: [TherapyProfileFixtures.decimal(0.85), 1]),
            .liveChanged,
            .profilesChanged,
            .recompute
        ])
        #expect(try settledAt(context) == date("2026-11-14 07:00"))
        let done = try #require(issued(context, "done").last)
        #expect(done.interruptionLevel == .active)
        #expect(done.backgroundContent.body.contains("as scheduled"))
        #expect(issued(context, "pending").last?.backgroundContent.body.contains("Default") == true)

        context.recorder.events = []
        await context.manager.runDueScheduledSwitch()
        #expect(context.recorder.pumpWrites == 0)
    }

    @Test("A start whose profile is already active settles without a switch") func alreadyActive() async throws {
        let context = try await makeContext()
        try await context.manager.activate("Weekend", expectedFingerprint: nil)
        context.recorder.now = date("2026-11-14 06:55")
        try await context.manager.activate("Default", expectedFingerprint: nil)
        try await context.manager.activate("Weekend", expectedFingerprint: nil)
        context.recorder.events = []
        context.recorder.now = date("2026-11-14 07:05")
        await context.manager.runDueScheduledSwitch()

        #expect(context.recorder.pumpWrites == 0)
        #expect(context.manager.activeProfileName == "Weekend")
        #expect(issued(context, "done").isEmpty)
    }

    @Test("A manual switch holds until the next start") func manualSwitchHolds() async throws {
        let context = try await makeContext()
        try await context.manager.save(weekend.renamed("Sport"), originalName: nil, baseFingerprint: nil)
        context.recorder.now = date("2026-11-14 07:03")
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        context.recorder.now = date("2026-11-14 07:10")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Sport")

        context.recorder.now = date("2026-11-16 06:01")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Default")
    }

    @Test("Of two missed starts only the newest runs") func newestOnly() async throws {
        let context = try await makeContext()
        context.recorder.now = date("2026-11-16 06:30")
        await context.manager.runDueScheduledSwitch()
        #expect(context.recorder.pumpWrites == 0)
        #expect(context.manager.activeProfileName == "Default")
        #expect(try settledAt(context) == date("2026-11-16 06:30"))
    }

    @Test("A start older than the grace is not applied and the user is told") func missed() async throws {
        let context = try await makeContext()
        context.recorder.now = date("2026-11-15 07:01")
        await context.manager.runDueScheduledSwitch()

        #expect(context.recorder.pumpWrites == 0)
        #expect(context.manager.activeProfileName == "Default")
        #expect(try settledAt(context) == date("2026-11-15 07:01"))
        let failed = try #require(issued(context, "failed").last)
        #expect(failed.interruptionLevel == .timeSensitive)
        #expect(failed.backgroundContent.body.contains("Weekend"))
    }

    @Test("A failed pump write changes nothing and is retried; success then says late") func pumpFailureRetried() async throws {
        let context = try await makeContext()
        let before = context.fileStorage.files
        context.recorder.pumpError = PumpFailure()
        context.recorder.now = date("2026-11-14 07:01")
        await context.manager.runDueScheduledSwitch()

        #expect(context.fileStorage.sameContents(as: before))
        #expect(context.manager.activeProfileName == "Default")
        #expect(try settledAt(context) == date("2026-11-13 12:00"))
        let pending = try #require(issued(context, "pending").last)
        #expect(pending.backgroundContent.body.contains("pump unreachable"))
        #expect(pending.trigger == .delayed(interval: 29 * 60))

        context.recorder.pumpError = nil
        context.recorder.now = date("2026-11-14 08:35")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Weekend")
        #expect(issued(context, "done").last?.backgroundContent.body.contains("done at") == true)
    }

    @Test("A suspended pump is retried like an unreachable one") func suspended() async throws {
        let context = try await makeContext()
        context.recorder.pumpSuspended = true
        context.recorder.now = date("2026-11-14 07:01")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Default")
        #expect(
            issued(context, "pending").last?.backgroundContent.body
                .contains(TherapyProfileError.pumpSuspended.localizedDescription) == true
        )

        context.recorder.pumpSuspended = false
        context.recorder.now = date("2026-11-14 07:20")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Weekend")
    }

    @Test("A delivered alert stays until its start is settled, also when a newer start is due") func deliveredAlertStays() async throws {
        let context = try await makeContext()
        try await context.manager.save(weekend.renamed("Sport"), originalName: nil, baseFingerprint: nil)
        try await context.manager.saveScheduledSwitches(
            context.manager.scheduledSwitches() + [ScheduledProfileSwitch(profileName: "Sport", weekday: 7, time: 27900)],
            baseFingerprint: nil
        )
        context.recorder.pumpSuspended = true
        context.recorder.now = date("2026-11-14 07:01")
        await context.manager.runDueScheduledSwitch()
        #expect(issued(context, "pending").last?.backgroundContent.body.contains("Weekend") == true)

        let calls = context.recorder.alerts.callLog.count
        context.recorder.now = date("2026-11-14 07:50")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.recorder.alerts.callLog.count == calls)

        context.recorder.pumpSuspended = false
        context.recorder.now = date("2026-11-14 07:55")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Sport")
        #expect(issued(context, "pending").last?.backgroundContent.body.contains("Default") == true)
    }

    @Test("A bolus in progress skips the run without a pump write") func bolusInProgress() async throws {
        let context = try await makeContext()
        context.recorder.bolusInProgress = true
        context.recorder.now = date("2026-11-14 07:01")
        await context.manager.runDueScheduledSwitch()
        #expect(context.recorder.pumpWrites == 0)
        #expect(try settledAt(context) == date("2026-11-13 12:00"))

        context.recorder.bolusInProgress = false
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Weekend")
    }

    @Test("A profile that no longer validates is settled and reported, not retried") func validationFailure() async throws {
        let context = try await makeContext()
        context.recorder.basalLimits = TherapyBasalLimits(supportedRates: [1, 2], maxBasal: 3)
        context.recorder.now = date("2026-11-14 07:01")
        await context.manager.runDueScheduledSwitch()

        #expect(context.recorder.pumpWrites == 0)
        #expect(try settledAt(context) == date("2026-11-14 07:01"))
        #expect(issued(context, "failed").last?.backgroundContent.body.contains("not supported by the pump") == true)
    }

    @Test("A failed save is settled and reported, also when the pump restore fails") func commitFailure() async throws {
        let context = try await makeContext()
        let before = context.fileStorage.files
        context.profileStorage.failsToStore = true
        context.recorder.pumpResults = [nil, PumpFailure()]
        context.recorder.now = date("2026-11-14 07:01")
        await context.manager.runDueScheduledSwitch()

        #expect(context.fileStorage.sameContents(as: before))
        #expect(context.manager.activeProfileName == "Default")
        #expect(context.recorder.pumpWrites == 2)
        #expect(try settledAt(context) == date("2026-11-14 07:01"))
        let failed = try #require(issued(context, "failed").last)
        #expect(failed.interruptionLevel == .timeSensitive)
        #expect(
            failed.backgroundContent.body.contains(
                TherapyProfileError.pumpRestoreFailed(pumpProfile: "Weekend", liveProfile: "Default").localizedDescription
            )
        )

        context.recorder.now = date("2026-11-14 07:10")
        await context.manager.runDueScheduledSwitch()
        #expect(context.recorder.pumpWrites == 2)
    }

    @Test("Deleting a profile removes its starts, renaming it keeps them") func renameAndDelete() async throws {
        let context = try await makeContext()
        try await context.manager.save(weekend.renamed("Free"), originalName: "Weekend", baseFingerprint: nil)
        #expect(context.manager.scheduledSwitches().map(\.profileName) == ["Default", "Free"])

        let removed = try await context.manager.delete("Free", expectedFingerprint: nil)
        #expect(removed == 1)
        #expect(context.manager.scheduledSwitches().map(\.profileName) == ["Default"])
    }

    @Test("A paused start does not run, and resuming catches nothing up") func pausedStart() async throws {
        let context = try await makeContext(paused: true)
        let pending = try #require(issued(context, "pending").last)
        #expect(pending.backgroundContent.body.contains("Default"))

        context.recorder.now = date("2026-11-14 07:01")
        await context.manager.runDueScheduledSwitch()
        #expect(context.recorder.pumpWrites == 0)
        #expect(try settledAt(context) == date("2026-11-13 12:00"))

        context.recorder.now = date("2026-11-14 07:10")
        var entries = context.manager.scheduledSwitches()
        entries = entries.map { entry in
            var entry = entry
            entry.paused = false
            return entry
        }
        try await context.manager.saveScheduledSwitches(entries, baseFingerprint: context.manager.scheduledSwitches().fingerprint)
        await context.manager.runDueScheduledSwitch()
        #expect(context.recorder.pumpWrites == 0)
        #expect(context.manager.activeProfileName == "Default")

        context.recorder.now = date("2026-11-21 07:00")
        await context.manager.runDueScheduledSwitch()
        #expect(context.manager.activeProfileName == "Weekend")
    }

    @Test("Without unpaused starts no alert stays armed") func allPaused() async throws {
        let context = try await makeContext()
        let entries = context.manager.scheduledSwitches().map { entry in
            var entry = entry
            entry.paused = true
            return entry
        }
        try await context.manager.saveScheduledSwitches(entries, baseFingerprint: nil)
        #expect(context.recorder.alerts.callLog.last == .retract(Alert.Identifier(
            managerIdentifier: "trio.therapyProfiles",
            alertIdentifier: "scheduledSwitch.pending"
        )))
    }

    @Test("A due start waits for a switch in progress") func serialized() async throws {
        let context = try await makeContext()
        try await context.manager.save(weekend.renamed("Sport"), originalName: nil, baseFingerprint: nil)
        let gate = AsyncGate()
        context.recorder.pumpGate = { await gate.wait() }
        context.recorder.now = date("2026-11-14 07:01")

        let manual = Task { try await context.manager.activate("Sport", expectedFingerprint: nil) }
        while context.recorder.pumpWrites == 0 { await Task.yield() }
        let scheduled = Task { await context.manager.runDueScheduledSwitch() }
        await gate.open()
        _ = try await manual.value
        await scheduled.value

        #expect(context.recorder.pumpWrites == 1)
        #expect(context.manager.activeProfileName == "Sport")
    }
}
