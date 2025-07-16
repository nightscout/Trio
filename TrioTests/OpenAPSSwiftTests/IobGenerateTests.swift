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
}
