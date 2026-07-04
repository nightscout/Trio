import Foundation
import Testing
@testable import Trio

@Suite("Calculate Temp Treatments Tests") struct CalculateTempTreatmentsTests {
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

    @Test("should calculate temp basals with defaults") func calculateTempBasalsWithDefaults() async throws {
        let basalprofile = createBasicBasalProfile()

        let now = Calendar.current.startOfDay(for: Date()) + 30.minutesToSeconds
        let timestamp30mAgo = now - 30.minutesToSeconds

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
            )
        ]

        var profile = Profile()
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.suspendZerosIob = false

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Filter temp basals (excluding zero temps)
        let tempBasals = treatments.filter { $0.rate != nil }

        // Test expected number of temp basals
        #expect(tempBasals.count == 2) // Original temp plus split zero temps

        // First entry should be actual temp basal
        #expect(tempBasals[0].rate == 2)
        #expect(tempBasals[0].duration == 30)

        // Following entries should be zero temps
        #expect(tempBasals[1].rate == 0)
        #expect(tempBasals[1].duration == 0)

        // 30m at 2 U/h - 1U/h -> 0.5U
        #expect(treatments.netInsulin().isWithin(0.01, of: 0.5))
    }

    @Test("should handle overlapping temp basals") func handleOverlappingTempBasals() async throws {
        let basalprofile = createBasicBasalProfile()

        let now = Calendar.current.startOfDay(for: Date()) + 30.minutesToSeconds
        let timestamp30mAgo = now - 30.minutesToSeconds
        let timestamp15mAgo = now - 15.minutesToSeconds

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
                type: .tempBasal,
                timestamp: timestamp15mAgo,
                durationMin: nil,
                rate: 3,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: timestamp15mAgo,
                durationMin: 30
            )
        ]

        var profile = Profile()
        profile.dia = 3
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.basalprofile = basalprofile
        profile.suspendZerosIob = false

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Get only non-zero temp basals
        let tempBasals = treatments.filter { ($0.rate ?? 0) > 0 && ($0.duration ?? 0) > 0 }
        #expect(tempBasals.count == 2)
        #expect(tempBasals[0].rate == 2)
        #expect(tempBasals[0].duration == 15)
        #expect(tempBasals[1].rate == 3)
        #expect(tempBasals[1].duration == 16)

        // in this case, the JS returns an incorrect adjusted tempBasal set
        // so we rely on counting the basals only
        // net 1 U/h for 15m and 2 U/h for 15m -> 0.75 U
        // but there is buggy rounding behavior so the answer will
        // be 0.8
        #expect(treatments.netInsulin().isWithin(0.01, of: 0.8))
    }

    @Test("should handle pump suspends and resumes") func handlePumpSuspendsAndResumes() async throws {
        let basalprofile = createBasicBasalProfile()

        let now = Calendar.current.startOfDay(for: Date()) + 30.minutesToSeconds
        let timestamp30mAgo = now - 30.minutesToSeconds
        let timestamp15mAgo = now - 15.minutesToSeconds

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
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        // Original temp should exist but be shortened
        let origTemp = treatments.first { $0.rate == 2 }
        #expect(origTemp != nil)
        #expect(origTemp?.duration == 15)

        // 15m at 2U/h - 1U/h -> 0.25U
        // 15m at 0U/h - 1U/h -> -0.25U
        // Total: 0
        #expect(treatments.netInsulin().isWithin(0.01, of: 0))
    }

    @Test("should handle basal profile changes") func handleBasalProfileChanges() async throws {
        let basalprofile = [
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

        let startingPoint = Calendar.current.startOfDay(for: Date())
        let endingPoint = startingPoint + 45.minutesToSeconds

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: startingPoint,
                duration: nil,
                rate: 3,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: startingPoint,
                durationMin: 60
            )
        ]
        var profile = Profile()
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1
        profile.maxDailyBasal = 2
        profile.suspendZerosIob = false

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: endingPoint,
            autosens: nil,
            zeroTempDuration: nil
        )

        let tempBasals = treatments.filter { ($0.rate ?? 0) != 0 && ($0.duration ?? 0) > 0 }
        #expect(!tempBasals.isEmpty)

        // Should split temp basal at profile change
        // Note: This is a little different from JS since we use the split output
        // and we divide up one tempbasal into two, but it should end up with the
        // same result for IoB
        #expect(tempBasals[0].rate == 3)

        // 30m at 3 U/h - 1 U/h -> 1U
        // 15m at 3 U/h - 2 U/h - 0.25U
        // 1.25U total
        print(treatments.prettyPrintedJSON!)
        #expect(treatments.netInsulin().isWithin(0.01, of: 1.25))
    }

    @Test("should properly record boluses") func properlyRecordBoluses() async throws {
        let basalprofile = createBasicBasalProfile()
        let now = Calendar.current.startOfDay(for: Date())

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .bolus,
                timestamp: now,
                amount: 2
            )
        ]

        var profile = Profile()
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.suspendZerosIob = false

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        let boluses = treatments.filter { $0.insulin != nil }
        #expect(boluses.count == 1)
        #expect(boluses[0].insulin == 2)
    }

    @Test("should add zero temp with specified duration") func addZeroTempWithSpecifiedDuration() async throws {
        let basalprofile = createBasicBasalProfile()

        let now = Calendar.current.startOfDay(for: Date()) + 30.minutesToSeconds
        let timestamp30mAgo = now - 30.minutesToSeconds

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
            )
        ]

        var profile = Profile()
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.suspendZerosIob = false

        // Test with 120 min zero temp duration
        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: 120
        )

        // Get only the zero temps
        let zeroTemps = treatments.filter { ($0.rate ?? 0) == 0 && ($0.duration ?? 0) > 0 }
        #expect(!zeroTemps.isEmpty)
        #expect(!zeroTemps.isEmpty)

        // Verify zero temp has correct duration
        let duration = zeroTemps.map({ $0.duration! }).reduce(0, +)
        #expect(duration == 120)

        // Verify zero temp starts 1 min in future
        let expectedStart = now + 60 // 1 minute in future
        #expect(zeroTemps[0].timestamp == expectedStart)

        // 30m at 2U/h - 1U/h -> 0.5
        // 120m at 0U/h - 1U/h -> -2.0
        // Total -> -1.5U
        #expect(treatments.netInsulin().isWithin(0.01, of: -1.5))
    }

    @Test("should handle zero temp with basal profile changes") func handleZeroTempWithBasalProfileChanges() async throws {
        let basalprofile = [
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

        let startingPoint = Calendar.current.startOfDay(for: Date())

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: startingPoint,
                duration: nil,
                rate: 3,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: startingPoint,
                durationMin: 60
            )
        ]

        var profile = Profile()
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1
        profile.maxDailyBasal = 2
        profile.suspendZerosIob = false

        // Test with 90 min zero temp duration
        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: startingPoint + 60.minutesToSeconds,
            autosens: nil,
            zeroTempDuration: 90
        )

        // Get zero temps
        let zeroTemps = treatments.filter { ($0.rate ?? 0) == 0 && ($0.duration ?? 0) > 0 }
        #expect(!zeroTemps.isEmpty)

        // Verify zero temp duration
        let duration = zeroTemps.map({ $0.duration! }).reduce(0, +)
        #expect(duration == 90)
        let expectedStart = startingPoint + 61.minutesToSeconds // 1 minute in future
        #expect(zeroTemps[0].timestamp == expectedStart)

        // 30m at 3U/h - 1U/h -> 1U
        // 30m at 3U/h - 2U/h -> 0.5U
        // 90m at 0U/h - 2U/h -> -3U
        // Total: -1.5U
        #expect(treatments.netInsulin().isWithin(0.01, of: -1.5))
    }

    @Test("should add zero temp when suspended") func addZeroTempWhenSuspended() async throws {
        let basalprofile = createBasicBasalProfile()

        let now = Calendar.current.startOfDay(for: Date()) + 30.minutesToSeconds
        let timestamp30mAgo = now - 30.minutesToSeconds
        let timestamp15mAgo = now - 15.minutesToSeconds

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
            )
        ]

        var profile = Profile()
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.suspendZerosIob = true

        // Test with 60 min zero temp duration
        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: 60
        )

        let tempBasals = treatments.filter { $0.type == .tempBasal }
        #expect(tempBasals[0].duration == 15)
        #expect(tempBasals[0].timestamp == timestamp30mAgo)
        #expect(tempBasals[0].rate == 2)

        // 15m at 2U/h - 1U/h -> 0.25U
        // 15m at 0U/h - 1U/h -> -0.25U
        // 60m at 0U/h - 1U/h -> -1
        // Total: -1U
        #expect(treatments.netInsulin().isWithin(0.01, of: -1))
    }

    @Test("should omit zero temp and split temp basal around suspend") func splitTempBasalFromSuspend() async throws {
        let basalprofile = [
            BasalProfileEntry(
                start: "00:00:00",
                minutes: 0,
                rate: 1.2
            )
        ]

        let now = Calendar.current.startOfDay(for: Date()) + 30.minutesToSeconds
        let timestamp30mAgo = now - 30.minutesToSeconds
        let timestamp20mAgo = now - 20.minutesToSeconds
        let timestamp10mAgo = now - 10.minutesToSeconds

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: timestamp30mAgo,
                duration: nil,
                rate: 2.4,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: timestamp30mAgo,
                durationMin: 30
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: timestamp20mAgo
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: timestamp10mAgo
            )
        ]

        var profile = Profile()
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1.2
        profile.maxDailyBasal = 1.2
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        let tempBasals = treatments.filter { $0.type == .tempBasal }
        #expect(tempBasals[0].duration == 10)
        #expect(tempBasals[0].timestamp == timestamp30mAgo)
        #expect(tempBasals[0].rate == 2.4)
        #expect(tempBasals[1].rate == 0)
        #expect(tempBasals.count == 2) // the original temp basal + last zero

        // 10m at 2.4U/h - 1.2U/h -> 0.2U
        // 10m at 0U/h - 1.2U/h -> -0.2U
        // 10m at 2.4U/h - 1.2U/h -> 0.2U
        // Total: 0.2
        #expect(treatments.netInsulin().isWithin(0.01, of: 0.2))
    }

    @Test("should produce -0.7 IoB") func zerosIoBAroundSuspend() async throws {
        let basalprofile = [
            BasalProfileEntry(
                start: "00:00:00",
                minutes: 0,
                rate: 0.65
            )
        ]

        let now = Calendar.current.startOfDay(for: Date()) + 60.minutesToSeconds

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasal,
                timestamp: now - 45.minutesToSeconds,
                duration: nil,
                rate: 0,
                temp: .absolute
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .tempBasalDuration,
                timestamp: now - 45.minutesToSeconds,
                durationMin: 60
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpSuspend,
                timestamp: now - 40.minutesToSeconds
            ),
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: now - 39.minutesToSeconds
            )
        ]

        var profile = Profile()
        profile.dia = 10
        profile.basalprofile = basalprofile
        profile.currentBasal = 0.65
        profile.maxDailyBasal = 0.65
        profile.suspendZerosIob = true

        let autosens = Autosens(ratio: 1.4, newisf: 29)

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: autosens,
            zeroTempDuration: nil
        )

        #expect(treatments.netInsulin().isWithin(0.01, of: -0.7))
    }

    @Test(
        "should handle temp basal overlapping resume with prior suspension"
    ) func handleTempBasalOverlappingResumeWithPriorSuspension() async throws {
        let basalprofile = createBasicBasalProfile()
        let now = Calendar.current.startOfDay(for: Date()) + 10.hoursToSeconds // Ensure we are well past 8h ago
        let resumeTime = now - 30.minutesToSeconds

        // Temp basal starts 10 mins before resume, lasts 40 mins.
        // So it ends 30 mins after resume.
        let tempStart = resumeTime - 10.minutesToSeconds
        let tempDuration = 40

        let pumpHistory = [
            ComputedPumpHistoryEvent.forTest(
                type: .pumpResume,
                timestamp: resumeTime
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
                durationMin: tempDuration
            )
        ]

        var profile = Profile()
        profile.dia = 3
        profile.basalprofile = basalprofile
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.suspendZerosIob = true

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: nil,
            zeroTempDuration: nil
        )

        let tempBasals = treatments.filter { $0.type == .tempBasal && $0.rate == 2 }

        #expect(tempBasals.count == 1)
        if let temp = tempBasals.first {
            // Should start at resumeTime
            #expect(temp.timestamp == resumeTime)
            // Should have duration of 30 minutes
            #expect(temp.duration == 30)
        }
    }
}
