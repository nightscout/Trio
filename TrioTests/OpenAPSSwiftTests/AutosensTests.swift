import Foundation
import Testing
@testable import Trio

@Suite("Autosens Temp Target Deviation Tests") struct TempTargetDeviationTests {
    // Helper function to create a basic profile with highTemptargetRaisesSensitivity enabled
    func createProfileWithSensitivity(enabled: Bool = true) -> Profile {
        var profile = Profile()
        profile.highTemptargetRaisesSensitivity = enabled
        return profile
    }

    // Helper function to create temp targets at specific times
    func createTempTarget(
        createdAt: Date,
        targetTop: Decimal,
        targetBottom: Decimal,
        duration: Decimal
    ) -> TempTarget {
        TempTarget(
            name: nil,
            createdAt: createdAt,
            targetTop: targetTop,
            targetBottom: targetBottom,
            duration: duration,
            enteredBy: nil,
            reason: nil,
            isPreset: nil,
            enabled: nil,
            halfBasalTarget: nil
        )
    }

    @Test("should return nil when highTemptargetRaisesSensitivity is false") func returnNilWhenSensitivityDisabled() async throws {
        let profile = createProfileWithSensitivity(enabled: false)
        let now = Date()
        let tempTargets = [
            createTempTarget(
                createdAt: now - 30.minutesToSeconds,
                targetTop: 140,
                targetBottom: 120,
                duration: 60
            )
        ]

        let result = AutosensGenerator.tempTargetDeviation(
            tempTargets: tempTargets,
            profile: profile,
            time: now
        )

        #expect(result == nil)
    }

    @Test("should return nil when no temp targets are active") func returnNilWhenNoActiveTempTargets() async throws {
        let profile = createProfileWithSensitivity()
        let now = Date()
        let tempTargets = [
            createTempTarget(
                createdAt: now - 120.minutesToSeconds, // 2 hours ago
                targetTop: 140,
                targetBottom: 120,
                duration: 60 // 1 hour duration, so expired
            )
        ]

        let result = AutosensGenerator.tempTargetDeviation(
            tempTargets: tempTargets,
            profile: profile,
            time: now
        )

        #expect(result == nil)
    }

    @Test("should return nil when temp target is at or below 100") func returnNilWhenTempTargetAtOrBelow100() async throws {
        let profile = createProfileWithSensitivity()
        let now = Date()
        let tempTargets = [
            createTempTarget(
                createdAt: now - 30.minutesToSeconds,
                targetTop: 100,
                targetBottom: 100,
                duration: 60
            )
        ]

        let result = AutosensGenerator.tempTargetDeviation(
            tempTargets: tempTargets,
            profile: profile,
            time: now
        )

        #expect(result == nil)
    }

    @Test("should calculate correct deviation for temp target above 100") func calculateCorrectDeviationAbove100() async throws {
        let profile = createProfileWithSensitivity()
        let now = Date()
        let tempTargets = [
            createTempTarget(
                createdAt: now - 30.minutesToSeconds,
                targetTop: 140,
                targetBottom: 120,
                duration: 60
            )
        ]

        let result = AutosensGenerator.tempTargetDeviation(
            tempTargets: tempTargets,
            profile: profile,
            time: now
        )

        // Average target = (140 + 120) / 2 = 130
        // Deviation = -(130 - 100) / 20 = -30 / 20 = -1.5
        #expect(result == -1.5)
    }
}

@Suite("Determine Last Site Change Tests") struct DetermineLastSiteChangeTests {
    @Test(
        "should return rewind timestamp when rewind event exists and rewindResetsAutosens is true"
    ) func returnRewindTimestampWhenRewindExists() async throws {
        let now = Date()
        let rewindTime = now - 6.hoursToSeconds

        let pumpHistory = [
            PumpHistoryEvent(
                id: "1",
                type: .tempBasal,
                timestamp: now - 1.hoursToSeconds,
                amount: nil,
                duration: nil,
                durationMin: nil,
                rate: 1.5,
                temp: .absolute,
                carbInput: nil
            ),
            PumpHistoryEvent(
                id: "2",
                type: .rewind,
                timestamp: rewindTime,
                amount: nil,
                duration: nil,
                durationMin: nil,
                rate: nil,
                temp: nil,
                carbInput: nil
            ),
            PumpHistoryEvent(
                id: "3",
                type: .tempBasal,
                timestamp: now - 12.hoursToSeconds,
                amount: nil,
                duration: nil,
                durationMin: nil,
                rate: 2.0,
                temp: .absolute,
                carbInput: nil
            )
        ]

        var profile = Profile()
        profile.rewindResetsAutosens = true

        let result = AutosensGenerator.determineLastSiteChange(
            pumpHistory: pumpHistory,
            profile: profile,
            clock: now
        )

        #expect(result == rewindTime)
    }
}
