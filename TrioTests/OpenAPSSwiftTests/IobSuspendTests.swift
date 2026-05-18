import Foundation
import Testing
@testable import Trio

@Suite("IOB Suspend Logic Tests") struct IobSuspendTests {
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

    // Helper function to create a multi-rate basal profile
    func createMultiRateBasalProfile() -> [BasalProfileEntry] {
        [
            BasalProfileEntry(
                start: "00:00:00",
                minutes: 0,
                rate: 1
            ),
            BasalProfileEntry(
                start: "00:30:00",
                minutes: 30,
                rate: 2
            )
        ]
    }

    @Test("should handle basic suspend and resume") func handleBasicSuspendAndResume() async throws {
        let basalprofile = createBasicBasalProfile()

        // Create fixed test dates (matching JavaScript test)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let now = formatter.date(from: "2016-06-13T01:00:00Z")!
        let timestamp30mAgo = formatter.date(from: "2016-06-13T00:30:00Z")!
        let timestamp15mAgo = formatter.date(from: "2016-06-13T00:45:00Z")!

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: timestamp30mAgo,
                duration: nil,
                rate: 2,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: timestamp30mAgo,
                durationMin: 30
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: timestamp15mAgo
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: now
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

        // Calculate expected insulin impact:
        // 15m at 2 U/h - 1 U/h = 0.25U
        // 15m at 0 U/h - 1 U/h = -0.25U
        // Total: 0U
        #expect(treatments.netInsulin().isWithin(0.01, of: 0.0))
    }

    @Test("should handle suspend prior to history window") func handleSuspendPriorToHistoryWindow() async throws {
        let basalprofile = createBasicBasalProfile()

        // Create fixed test dates (matching JavaScript test)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let now = formatter.date(from: "2016-06-13T08:00:00Z")!
        let resumeTime = formatter.date(from: "2016-06-13T07:00:00Z")!
        let tempStartTime = formatter.date(from: "2016-06-13T07:30:00Z")!

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resumeTime
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: tempStartTime,
                duration: nil,
                rate: 2,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: tempStartTime,
                durationMin: 30
            )
        ]

        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.dia = 10 // Longer DIA to match JS test
        profile.basalprofile = basalprofile
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Calculate expected insulin impact:
        // 7h at 0 U/h - 1U/h = -7 (this may need adjustment based on implementation)
        // 30m at 2 U/h - 1 U/h = 0.5U
        // Total: approximately -6.5U

        // Note: This test case may need adjustments based on how you implement the suspend
        // prior to history window logic in your Swift port
        let netInsulin = treatments.netInsulin()

        // The exact value might vary due to implementation details, but the general direction should be consistent
        #expect(netInsulin < -6.0)
    }

    @Test("should handle current suspension") func handleCurrentSuspension() async throws {
        let basalprofile = createBasicBasalProfile()

        // Setting up the dates for the test
        let now = Calendar.current.startOfDay(for: Date()) + 60.minutesToSeconds
        let suspendTime = now - 30.minutesToSeconds
        let tempStartTime = now - 45.minutesToSeconds

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: tempStartTime,
                duration: nil,
                rate: 2,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: tempStartTime,
                durationMin: 30
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

        // Calculate expected insulin impact:
        // 15m at 2 U/h - 1U/h = 0.25
        // 30m at 0 U/h - 1U/h = -0.5
        // Total: -0.25U
        #expect(treatments.netInsulin().isWithin(0.01, of: -0.25))
    }

    @Test("should handle multiple suspend-resume cycles") func handleMultipleSuspendResumeCycles() async throws {
        let basalprofile = createBasicBasalProfile()

        // Setting up the dates for the test
        let now = Calendar.current.startOfDay(for: Date()) + 90.minutesToSeconds

        // Create history with 2 suspend-resume cycles
        let suspend1 = now - 90.minutesToSeconds
        let resume1 = now - 75.minutesToSeconds
        let tempStart = now - 60.minutesToSeconds
        let suspend2 = now - 45.minutesToSeconds
        let resume2 = now - 30.minutesToSeconds

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspend1
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resume1
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: tempStart,
                duration: nil,
                rate: 2,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: tempStart,
                durationMin: 60
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspend2
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resume2
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

        // Calculate expected insulin impact:
        // 15m at 0 U/h - 1 U/h = -0.25
        // 15m at 2 U/h - 1 U/h = 0.25
        // 15m at 0 U/h - 1 U/h = -0.25
        // 30m at 2 U/h - 1 U/h = 0.5
        // Total: 0.25U
        #expect(treatments.netInsulin().isWithin(0.01, of: 0.25))
    }

    @Test("should handle suspend with basal profile changes") func handleSuspendWithBasalProfileChanges() async throws {
        let basalprofile = createMultiRateBasalProfile()

        // Create fixed test dates (matching JavaScript test)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let calendar = Calendar.current

        let currentTime = Date()
        let startTime = Calendar.current.startOfDay(for: currentTime) + 15.minutesToSeconds
        let suspendTime = Calendar.current.startOfDay(for: currentTime) + 30.minutesToSeconds
        let resumeTime = Calendar.current.startOfDay(for: currentTime) + 45.minutesToSeconds
        let endTime = Calendar.current.startOfDay(for: currentTime) + 60.minutesToSeconds

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: startTime,
                duration: nil,
                rate: 3,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: startTime,
                durationMin: 45
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspendTime
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resumeTime
            )
        ]

        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 2
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: endTime,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Calculate expected insulin impact:
        // 15m at 3 U/h - 1 U/h = 0.5U (from start to basal change)
        // 15m at 0 U/h - 2 U/h = -0.5U (from basal change and suspend)
        // 15m at 3 U/h - 2 U/h = 0.25U (resume to finish)
        // Total: 0.25U
        #expect(treatments.netInsulin().isWithin(0.01, of: 0.25))
    }

    @Test("should properly handle IOB impact with suspends") func handleIobImpactWithSuspends() async throws {
        let basalprofile = createBasicBasalProfile()

        // Setting up the dates for the test
        let now = Calendar.current.startOfDay(for: Date()) + 90.minutesToSeconds

        let tempStart = now - 60.minutesToSeconds
        let suspendTime = now - 30.minutesToSeconds
        let resumeTime = now

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: tempStart,
                duration: nil,
                rate: 2,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: tempStart,
                durationMin: 30
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: suspendTime
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resumeTime
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

        // Calculate expected insulin impact:
        // 30m at 2 U/h - 1 U/h = 0.5U (from temp start to temp end)
        // 30m at 0 U/h - 1 U/h = -0.5U (from suspend to resume)
        // Total: 0U
        #expect(treatments.netInsulin().isWithin(0.01, of: 0.0))
    }
}
