import Foundation
import Testing
@testable import Trio

@Suite("IoB generate tests") struct IobGenerateTests {
    /// One of our performance optimizations where we filter old pump events has subtle interactions
    /// with the JS implementation. In particular, JS will hardcode 8 hours for DIA in the suspend logic
    /// when a pump history has a resume as the first suspend/resume event. This hard coded value
    /// can cause some old netbasalinsulin to get dropped if DIA > 8 hours. We fixed this bug by
    /// not filtering suspend and resume events, and this test case checks for the bug fix.
    @Test("should test suspend filtering") func testSuspendFiltering() async throws {
        let now = Calendar.current.startOfDay(for: Date()) + 20.hoursToSeconds

        let history = [
            PumpHistoryEvent(id: UUID().uuidString, type: .pumpSuspend, timestamp: now - 15.hoursToSeconds),
            PumpHistoryEvent(id: UUID().uuidString, type: .pumpResume, timestamp: now - 1.hoursToSeconds)
        ]

        var profile = Profile()
        profile.dia = 10
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.basalprofile = [
            BasalProfileEntry(
                start: "00:00:00",
                minutes: 0,
                rate: 1
            )
        ]
        profile.suspendZerosIob = true

        let iob = try IobGenerator.generate(history: history, profile: profile, clock: now, autosens: nil)

        // Matches the long suspend test in JS iob.test.js
        #expect(iob[0].netbasalinsulin == -8.95)
    }

    /// With no temp basal in pump history (e.g. open loop on scheduled basal), `lastTemp` is written as
    /// `{"date": 0}`. The Nightscout upload reads monitor/iob.json back as `[IOBEntry]`, and must not
    /// fail on that, or the uploaded device status silently loses its `iob`.
    @Test("IOB without a temp basal reads back as IOBEntry") func testIobWithoutTempBasalDecodesAsIOBEntry() async throws {
        let now = Calendar.current.startOfDay(for: Date()) + 20.hoursToSeconds

        let history = [
            PumpHistoryEvent(id: UUID().uuidString, type: .bolus, timestamp: now - 1.hoursToSeconds, amount: 1)
        ]

        var profile = Profile()
        profile.dia = 5
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.basalprofile = [
            BasalProfileEntry(
                start: "00:00:00",
                minutes: 0,
                rate: 1
            )
        ]

        let iob = try IobGenerator.generate(history: history, profile: profile, clock: now, autosens: nil)
        #expect(iob[0].lastTemp?.rate == nil)

        let data = try JSONCoding.encoder.encode(iob)
        let entries = try JSONCoding.decoder.decode([IOBEntry].self, from: data)

        #expect(entries.first?.iob == iob[0].iob)
        #expect(entries.first?.lastTemp?.date == 0)
        #expect(entries.first?.lastTemp?.rate == nil)
    }
}
