import Foundation
import Testing
@testable import Trio

@Suite("Consecutive Pump Suspend/Resume Events Tests") struct IobConsecutiveEventsTests {
    // Helper function to create a basic basal profile
    func createBasicBasalProfile() -> [BasalProfileEntry] {
        [
            BasalProfileEntry(
                start: "00:00:00",
                minutes: 0,
                rate: 1
            )
        ]
    }

    @Test(
        "should treat two consecutive PumpSuspend events as a single, longer suspend from the first event"
    ) func consecutivePumpSuspendEvents() async throws {
        let basalprofile = createBasicBasalProfile()
        let now = Calendar.current.startOfDay(for: Date()) + 60.minutesToSeconds // Current time 01:00

        let suspendTime1 = now - 45.minutesToSeconds // Suspend 1 at 00:15
        let suspendTime2 = now - 30.minutesToSeconds // Suspend 2 at 00:30
        let resumeTime = now - 15.minutesToSeconds // Resume at 00:45

        // JS: reversed chronological order (newest first)
        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resumeTime
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspendTime2
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspendTime1
            )
        ]

        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Check total insulin impact for the period:
        // It should produce -0.5U being suspended for 30m total
        #expect(treatments.netInsulin().isWithin(0.05, of: -0.5))
    }

    @Test(
        "should consider only the first PumpResume after a suspend event, ignoring subsequent consecutive resumes"
    ) func consecutivePumpResumeEvents() async throws {
        let basalprofile = createBasicBasalProfile()
        let now = Calendar.current.startOfDay(for: Date()) + 60.minutesToSeconds // Current time 01:00

        let suspendTime = now - 45.minutesToSeconds // Suspend at 00:15
        let resumeTime1 = now - 30.minutesToSeconds // Resume 1 at 00:30
        let resumeTime2 = now - 15.minutesToSeconds // Resume 2 at 00:45

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resumeTime2
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resumeTime1
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspendTime
            )
        ]

        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Check total insulin impact for the period:
        // suspended for 15m, should be -0.25U
        #expect(treatments.netInsulin().isWithin(0.05, of: -0.25))
    }

    @Test(
        "should correctly process a complex sequence of suspend, suspend, resume, resume, suspend, resume events"
    ) func complexSequenceEvents() async throws {
        let basalprofile = createBasicBasalProfile()
        let now = Calendar.current.startOfDay(for: Date()) + 90.minutesToSeconds // Current time 01:30

        let suspend1 = now - 75.minutesToSeconds // Suspend 1 at 00:15
        let suspend2 = now - 60.minutesToSeconds // Suspend 2 at 00:30
        let resume1 = now - 45.minutesToSeconds // Resume 1 at 00:45
        let resume2 = now - 30.minutesToSeconds // Resume 2 at 01:00
        let suspend3 = now - 15.minutesToSeconds // Suspend 3 at 01:15
        let resume3 = now // Resume 3 at 01:30 (current time)

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resume3
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspend3
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resume2
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resume1
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspend2
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspend1
            )
        ]

        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Total insulin calculation:
        // Suspended for 45m total, should produce -0.75U
        #expect(treatments.netInsulin().isWithin(0.05, of: -0.75))
    }
}
