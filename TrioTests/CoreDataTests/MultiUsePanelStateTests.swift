import Foundation
import Testing

@testable import Trio

@Suite("Multi-Use Panel State Tests") struct MultiUsePanelStateTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var fresh: Date { now.addingTimeInterval(-5 * 60) }
    private var stale: Date { now.addingTimeInterval(-20 * 60) }

    private func resolve(
        notificationsDisabled: Bool = false,
        pumpTimeMismatch: Bool = false,
        lastGlucoseDate: Date?,
        maxIOB: Decimal = 10,
        hasUnacknowledgedReleaseNotes: Bool = false
    ) -> MultiUsePanelState {
        MultiUsePanelState.resolve(
            notificationsDisabled: notificationsDisabled,
            pumpTimeMismatch: pumpTimeMismatch,
            lastGlucoseDate: lastGlucoseDate,
            maxIOB: maxIOB,
            hasUnacknowledgedReleaseNotes: hasUnacknowledgedReleaseNotes,
            now: now
        )
    }

    @Test("All healthy shows stats") func testStatsDefault() {
        #expect(resolve(lastGlucoseDate: fresh) == .stats)
    }

    @Test("Missing notifications outranks everything") func testNotificationsTop() {
        #expect(resolve(
            notificationsDisabled: true,
            pumpTimeMismatch: true,
            lastGlucoseDate: nil,
            maxIOB: 0
        ) == .notificationsDisabled)
    }

    @Test("Pump time mismatch outranks CGM and MaxIOB") func testTimeMismatchSecond() {
        #expect(resolve(pumpTimeMismatch: true, lastGlucoseDate: nil, maxIOB: 0) == .pumpTimeMismatch)
    }

    @Test("Stale glucose outranks MaxIOB") func testCgmStaleThird() {
        #expect(resolve(lastGlucoseDate: stale, maxIOB: 0) == .cgmStale)
    }

    @Test("No glucose at all counts as stale") func testNoGlucoseIsStale() {
        #expect(resolve(lastGlucoseDate: nil) == .cgmStale)
    }

    @Test("Fresh glucose within threshold is not stale") func testFreshGlucose() {
        #expect(resolve(lastGlucoseDate: now.addingTimeInterval(-11 * 60)) == .stats)
    }

    @Test("MaxIOB zero shows its warning") func testMaxIOBZero() {
        #expect(resolve(lastGlucoseDate: fresh, maxIOB: 0) == .maxIOBZero)
    }

    @Test("Unacknowledged release notes displace the stats") func testWhatsNewOverStats() {
        #expect(resolve(lastGlucoseDate: fresh, hasUnacknowledgedReleaseNotes: true) == .whatsNew)
    }

    @Test("Every warning outranks release notes") func testWhatsNewYieldsToWarnings() {
        #expect(resolve(
            notificationsDisabled: true,
            lastGlucoseDate: fresh,
            hasUnacknowledgedReleaseNotes: true
        ) == .notificationsDisabled)
        #expect(resolve(
            pumpTimeMismatch: true,
            lastGlucoseDate: fresh,
            hasUnacknowledgedReleaseNotes: true
        ) == .pumpTimeMismatch)
        #expect(resolve(lastGlucoseDate: stale, hasUnacknowledgedReleaseNotes: true) == .cgmStale)
        #expect(resolve(
            lastGlucoseDate: fresh,
            maxIOB: 0,
            hasUnacknowledgedReleaseNotes: true
        ) == .maxIOBZero)
    }

    @Test("Acknowledged release notes fall back to stats") func testAcknowledgedShowsStats() {
        #expect(resolve(lastGlucoseDate: fresh, hasUnacknowledgedReleaseNotes: false) == .stats)
    }
}
