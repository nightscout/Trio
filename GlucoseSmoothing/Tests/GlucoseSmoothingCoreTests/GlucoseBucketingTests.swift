@testable import GlucoseSmoothingCore
import XCTest

/// AAPS-faithful 5-minute bucketing (`GlucoseBucketing`) applied to the smoother's input in the
/// production path, plus the write-back projection back onto per-reading timestamps. Regression cover
/// for the sub-2-minute-spacing "V-spike" glitch: a CGM reading `< 2 min` after the previous one used
/// to start a new segment that re-initialised the filter from the raw value, spiking the line.
final class GlucoseBucketingTests: XCTestCase {
    private let anchor: Int64 = 1_700_000_000_000

    /// Build newest-first from (minuteOffset, value) pairs given oldest-first.
    private func series(_ pairs: [(Int, Double)]) -> [InMemoryGlucoseValue] {
        pairs.map { InMemoryGlucoseValue(timestamp: anchor + Int64($0.0) * 60000, value: $0.1) }
            .reversed()
    }

    /// The real tester trace (anonymized: minute-of-day offset + glucose), oldest-first.
    private func testerTrace() -> [(Int, Double)] {
        [
            (427, 72), (432, 71), (437, 77), (442, 69), (447, 70), (452, 91), (457, 82), (462, 99),
            (467, 105), (472, 111), (477, 115), (482, 129), (487, 125), (492, 146), (497, 152),
            (502, 146), (507, 151), (512, 157), (517, 163), (522, 173), (527, 171), (532, 155),
            (537, 151), (542, 163), (547, 150), (552, 152), (557, 144), (562, 136), (566, 124),
            (567, 116), (572, 110), (581, 102), (586, 86), (591, 85), (596, 85), (601, 75),
            (611, 80), (612, 65), (617, 78), (619, 70), (624, 84), (629, 85), (634, 96), (635, 98), (640, 86)
        ]
    }

    // Regular 5-min data must keep its values (only timestamps normalize) → per-call parity preserved.
    func testRegular5minDataPreservesValues() {
        let s = series((0 ..< 20).map { ($0 * 5, 100.0 + Double($0)) })
        XCTAssertTrue(GlucoseBucketing.isAbout5minData(s), "exact 5-min data must be detected as 5-min")
        let bucketed = GlucoseBucketing.bucketed(s)
        XCTAssertEqual(bucketed.count, s.count, "regular data keeps its point count")
        for (a, b) in zip(bucketed, s) {
            XCTAssertEqual(a.value, b.value, accuracy: 1E-9, "regular 5-min values pass through unchanged")
        }
    }

    // The tester trace has sub-2-min pairs → NOT 5-min data → recalculated resampling.
    func testTesterTraceDetectedAsIrregular() {
        XCTAssertFalse(GlucoseBucketing.isAbout5minData(series(testerTrace())), "sub-2-min spacing → not 5-min")
    }

    // Core regression: the 10:12 (offset 612) reading no longer produces a downward spike after bucketing.
    func testSubMinuteSpacingSpikeRemoved() {
        let raw = series(testerTrace())

        // BEFORE (raw smoothing): the isolated 10:12 reading re-inits a segment → stored ~raw (spike).
        let before = UnscentedKalmanFilter().smooth(raw)
        let ts612 = anchor + Int64(612) * 60000
        let ts611 = anchor + Int64(611) * 60000
        let beforeAt612 = before.first { $0.timestamp == ts612 }?.smoothed
        XCTAssertNotNil(beforeAt612)
        XCTAssertLessThan(beforeAt612!, 68, "pre-fix: 10:12 spikes down to ~raw (65→64)")

        // AFTER (production path): bucket → smooth → interpolate back onto each row's timestamp.
        let grid = UnscentedKalmanFilter().smooth(GlucoseBucketing.bucketed(raw))
        let after612 = GlucoseBucketing.interpolatedSmoothed(at: ts612, grid: grid)
        let after611 = GlucoseBucketing.interpolatedSmoothed(at: ts611, grid: grid)
        XCTAssertNotNil(after612)
        XCTAssertNotNil(after611)
        // No downward spike: the stored value tracks the ~76 trend, not the isolated raw 65.
        XCTAssertGreaterThan(after612!, 72, "post-fix: 10:12 follows the smoothed trend, no spike")
        // No near-vertical step between adjacent stored rows across the former break.
        XCTAssertLessThan(abs(after612! - after611!), 4, "post-fix: no vertical jump at 10:11→10:12")
    }

    // Interpolation clamps to the grid endpoints outside the grid's time span.
    func testInterpolationClampsAtEdges() {
        var grid = series((0 ..< 5).map { ($0 * 5, 100.0) })
        for i in grid.indices { grid[i].smoothed = grid[i].value } // newest-first, all 100
        let newest = grid[0].timestamp, oldest = grid.last!.timestamp
        XCTAssertEqual(GlucoseBucketing.interpolatedSmoothed(at: newest + 60000, grid: grid) ?? .nan, 100, accuracy: 1E-9)
        XCTAssertEqual(GlucoseBucketing.interpolatedSmoothed(at: oldest - 60000, grid: grid) ?? .nan, 100, accuracy: 1E-9)
    }
}
