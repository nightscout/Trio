import Foundation
import Testing
@testable import Trio

@Suite("Target Profile") struct TargetTests {
    let standardTargets = BGTargets(
        units: .mgdL,
        userPreferredUnits: .mgdL,
        targets: [
            BGTargetEntry(low: 100, high: 120, start: "00:00:00", offset: 0),
            BGTargetEntry(low: 90, high: 110, start: "03:00:00", offset: 180),
            BGTargetEntry(low: 110, high: 130, start: "06:00:00", offset: 360)
        ]
    )

    let tempTargets = [
        TempTarget(
            name: nil,
            createdAt: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 2))!,
            targetTop: 100,
            targetBottom: 80,
            duration: 120,
            enteredBy: nil,
            reason: nil,
            isPreset: nil,
            enabled: nil,
            halfBasalTarget: nil
        )
    ]

    let profile = Profile()

    @Test("should return correct target from schedule") func correctTargetFromSchedule() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 1))!
        let (_, result) = try Targets
            .bgTargetsLookup(targets: standardTargets, tempTargets: tempTargets, profile: profile, now: now)
        #expect(result.high == 100)
        #expect(result.low == 100)
    }

    @Test("should override from Profile targetBg") func profileOverride() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 1))!
        var profile = Profile()
        profile.targetBg = 110
        let (_, result) = try Targets
            .bgTargetsLookup(targets: standardTargets, tempTargets: tempTargets, profile: profile, now: now)
        #expect(result.high == 110)
        #expect(result.low == 110)
    }

    @Test("should handle target schedule changes") func handleScheduleChanges() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 4))!
        let (_, result) = try Targets
            .bgTargetsLookup(targets: standardTargets, tempTargets: tempTargets, profile: profile, now: now)
        #expect(result.high == 90)
        #expect(result.low == 90)
    }

    @Test("should handle temp targets") func handleTempTargets() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 2, minute: 30))!
        let (_, result) = try Targets
            .bgTargetsLookup(targets: standardTargets, tempTargets: tempTargets, profile: profile, now: now)
        #expect(result.high == 100)
        #expect(result.low == 80)
        #expect(result.temptargetSet == true)
    }

    @Test("should handle temp target cancellation") func handleTempTargetCancellation() async throws {
        let cancelTempTargets = [
            TempTarget(
                name: nil,
                createdAt: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 2, minute: 30))!,
                targetTop: 0,
                targetBottom: 0,
                duration: 0,
                enteredBy: nil,
                reason: nil,
                isPreset: nil,
                enabled: nil,
                halfBasalTarget: nil
            )
        ]
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 2, minute: 45))!
        let (_, result) = try Targets
            .bgTargetsLookup(targets: standardTargets, tempTargets: cancelTempTargets, profile: profile, now: now)
        #expect(result.high == 100)
        #expect(result.low == 100)
    }

    @Test("should enforce hard limits on target range") func enforceHardLimits() async throws {
        let extremeTargets = BGTargets(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            targets: [
                BGTargetEntry(low: 40, high: 250, start: "00:00:00", offset: 0)
            ]
        )
        let (_, result) = try Targets.bgTargetsLookup(targets: extremeTargets, tempTargets: [], profile: profile)
        #expect(result.maxBg == 80)
        #expect(result.minBg == 80)
    }
}
