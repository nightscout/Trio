@testable import GlucoseSmoothingCore
import XCTest

/// Across-restart persistence parity with AndroidAPS. AAPS's smoothing plugin saves `learnedR`,
/// `lastProcessedTimestamp` and `sensorSessionId` to preferences and reloads them on construction
/// (rejecting an out-of-range `learnedR`). Trio mirrors that via `persistedState` / `restore(_:)`.
final class UkfPersistenceTests: XCTestCase {
    private func series(_ values: [Double], stepMin: Int64 = 5) -> [InMemoryGlucoseValue] {
        let base: Int64 = 1_700_000_000_000
        return values.enumerated().map { i, v in
            InMemoryGlucoseValue(timestamp: base - Int64(i) * stepMin * 60000, value: v)
        }
    }

    func testPersistedStateRoundTrips() {
        let f = UnscentedKalmanFilter()
        let saved = UnscentedKalmanFilter.PersistedState(
            learnedR: 42.5, lastProcessedTimestamp: 1_700_000_000_000, sensorSessionId: 7
        )
        f.restore(saved)
        XCTAssertEqual(f.persistedState, saved, "restore then read must round-trip the persisted state")
    }

    func testRestoreRejectsOutOfBoundsLearnedR() {
        // Above rMax (225) and below rMin (16) must fall back to rInit (25); an in-range value is kept.
        let hi = UnscentedKalmanFilter()
        hi.restore(.init(learnedR: 10_000, lastProcessedTimestamp: 1, sensorSessionId: 1))
        XCTAssertEqual(hi.persistedState.learnedR, 25.0, "out-of-range (high) R must reset to rInit")

        let lo = UnscentedKalmanFilter()
        lo.restore(.init(learnedR: 0.0, lastProcessedTimestamp: 1, sensorSessionId: 1))
        XCTAssertEqual(lo.persistedState.learnedR, 25.0, "out-of-range (low) R must reset to rInit")

        let ok = UnscentedKalmanFilter()
        ok.restore(.init(learnedR: 120.0, lastProcessedTimestamp: 1, sensorSessionId: 1))
        XCTAssertEqual(ok.persistedState.learnedR, 120.0, "in-range R must be kept")
        // …but timestamp and session are always carried.
        XCTAssertEqual(hi.persistedState.lastProcessedTimestamp, 1)
        XCTAssertEqual(hi.persistedState.sensorSessionId, 1)
    }

    func testSmoothingUpdatesPersistableState() {
        // A long noisy run (past the ≥12-innovation gate before R adapts) must move learnedR off its
        // default and advance lastProcessedTimestamp — so there is real state to persist.
        let vals: [Double] = (0 ..< 60).map { i in
            let wave: Double = 30.0 * sin(Double(i) * 0.7)
            let jitter: Double = i % 2 == 0 ? 8.0 : -8.0
            return 110.0 + wave + jitter
        }
        let f = UnscentedKalmanFilter()
        _ = f.smooth(series(vals))
        XCTAssertNotEqual(f.persistedState.learnedR, 25.0, "learnedR should adapt away from rInit on noisy data")
        XCTAssertEqual(f.persistedState.lastProcessedTimestamp, 1_700_000_000_000, "newest timestamp recorded")
    }

    func testRestoredLearnedRAffectsSmoothing() {
        // Restoring a high learned noise (max) — with a RECENT lastProcessedTimestamp so it isn't
        // reset as stale — vs a fresh filter must change the estimate over a short window (<12 pts, so
        // R does not re-adapt), proving the persisted R is actually used.
        let base: Int64 = 1_700_000_000_000
        let vals = [100.0, 140.0, 100.0, 138.0, 102.0]
        let restored = UnscentedKalmanFilter()
        restored.restore(.init(learnedR: 225.0, lastProcessedTimestamp: base - 5 * 60000, sensorSessionId: 3))
        let restoredOut = restored.smooth(series(vals))[0].smoothed

        let fresh = UnscentedKalmanFilter()
        let freshOut = fresh.smooth(series(vals))[0].smoothed

        XCTAssertNotNil(restoredOut)
        XCTAssertNotNil(freshOut)
        XCTAssertNotEqual(restoredOut!, freshOut!, "a restored learnedR must change smoothing vs a fresh filter")
    }
}
