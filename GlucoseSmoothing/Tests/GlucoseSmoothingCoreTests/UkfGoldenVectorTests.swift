@testable import GlucoseSmoothingCore
import XCTest

/// Golden-vector parity for the Swift UKF port — the 9 behaviours the shipped AndroidAPS Kotlin
/// unit test asserts (`UnscentedKalmanFilterPluginTest.kt`), same input vectors and thresholds.
/// These are the formal correctness gate: the Swift port must reproduce them op-for-op, exactly as
/// the reference Python `benchmark.py` aborts unless its UKF passes the same 9.
final class UkfGoldenVectorTests: XCTestCase {
    /// Guard-disabled by default (IOB unavailable → 99.0 → compression gate off), matching the
    /// Kotlin test's default plugin. The compression test supplies a stubbed IOB.
    private func filter(iob: Double? = nil) -> UnscentedKalmanFilter {
        if let iob { return UnscentedKalmanFilter(iobProvider: { iob }) }
        return UnscentedKalmanFilter()
    }

    /// Newest-first series (index 0 = most recent) at `stepMin`-minute spacing, timestamps descending.
    private func series(_ values: [Double], stepMin: Int64 = 5) -> [InMemoryGlucoseValue] {
        let base: Int64 = 1_700_000_000_000
        return values.enumerated().map { i, v in
            InMemoryGlucoseValue(timestamp: base - Int64(i) * stepMin * 60_000, value: v)
        }
    }

    func testEmptyInputReturnsTheSameEmptyList() {
        let out = filter().smooth([])
        XCTAssertTrue(out.isEmpty)
    }

    func testSingleValueIsCopiedToSmoothedFlooredAt39() {
        XCTAssertEqual(filter().smooth(series([100]))[0].smoothed, 100.0)
        XCTAssertEqual(filter().smooth(series([20]))[0].smoothed, 39.0)
    }

    func testErrorCode38ValuesCollapseToThe39FloorWithNoValidSegment() {
        let out = filter().smooth(series([38, 38, 38]))
        XCTAssertEqual(out.map(\.smoothed), [39.0, 39.0, 39.0])
    }

    func testACleanSeriesSmoothsEveryPointToASaneValue() {
        let out = filter().smooth(series([101, 99, 100, 102, 98, 100, 101, 99, 100, 100]))
        XCTAssertEqual(out.count, 10)
        for v in out {
            XCTAssertNotNil(v.smoothed)
            XCTAssertGreaterThanOrEqual(v.smoothed!, 39.0)
            XCTAssertEqual(v.smoothed!, 100.0, accuracy: 30.0)
        }
    }

    func testARisingSeriesProducesARisingSmoothedTrend() {
        // newest-first: data[0] is the most recent (highest), data.last() the oldest (lowest).
        let out = filter().smooth(series([150, 140, 130, 120, 110, 100, 90, 80]))
        XCTAssertGreaterThan(out.first!.smoothed!, out.last!.smoothed!)
    }

    func testAnIsolatedSpikeIsDampenedTowardTheSurroundingLevel() {
        let out = filter().smooth(series([100, 100, 100, 300, 100, 100, 100, 100]))
        let spike = out[3]
        XCTAssertEqual(spike.value, 300.0)
        XCTAssertLessThan(spike.smoothed!, 200.0)
    }

    func testDataSpanningAMajorGapIsSplitIntoSegmentsAndBothClustersAreSmoothed() {
        let base: Int64 = 1_700_000_000_000
        let clusterA = [100.0, 101.0, 99.0].enumerated().map { i, v in
            InMemoryGlucoseValue(timestamp: base - Int64(i) * 5 * 60_000, value: v)
        }
        let gapBase = base - Int64(3 * 5 + 120) * 60_000 // 120-min (major) gap after cluster A
        let clusterB = [120.0, 119.0, 121.0].enumerated().map { i, v in
            InMemoryGlucoseValue(timestamp: gapBase - Int64(i) * 5 * 60_000, value: v)
        }
        let out = filter().smooth(clusterA + clusterB)
        XCTAssertGreaterThanOrEqual(out.filter { $0.smoothed != nil }.count, 4)
    }

    func testSmoothingIsDeterministicAcrossFreshInstances() {
        let a = filter().smooth(series([120, 118, 122, 119, 121, 120, 118]))
        let b = filter().smooth(series([120, 118, 122, 119, 121, 120, 118]))
        for i in a.indices { XCTAssertEqual(b[i].smoothed!, a[i].smoothed!, accuracy: 1e-9) }
    }

    func testOrphanPointsIsolatedByAGapAreFilledNotLeftNil() {
        // Two leading (newest) points isolated by a 90-min gap from a 3-point segment join no segment
        // (run < 3). They must be filled with their floored raw value — never returned nil — matching
        // the reference Python V4UKF and keeping the `.smoothed` contract for Seam-1 consumers.
        let base: Int64 = 1_700_000_000_000
        let step: Int64 = 5 * 60_000
        let readings = [
            InMemoryGlucoseValue(timestamp: base, value: 105),
            InMemoryGlucoseValue(timestamp: base - step, value: 103),
            InMemoryGlucoseValue(timestamp: base - step - 90 * 60_000, value: 120),
            InMemoryGlucoseValue(timestamp: base - step - 95 * 60_000, value: 119),
            InMemoryGlucoseValue(timestamp: base - step - 100 * 60_000, value: 121),
        ]
        let out = filter().smooth(readings)
        for v in out { XCTAssertNotNil(v.smoothed, "every returned point must have a smoothed value") }
        XCTAssertEqual(out[0].smoothed, 105.0) // orphan → floored raw
        XCTAssertEqual(out[1].smoothed, 103.0)
    }

    func testACompressionLowWithNearZeroIobIsDampedNotTrackedToTheFloor() {
        // newest-first: steady ~100 then a steep fall toward 40 (a compression dip).
        let vals: [Double] = [40, 44, 60, 82, 100, 100, 100, 100]
        let damped = filter(iob: 0.1).smooth(series(vals))[0].smoothed!
        // With real insulin on board (guard disabled) the same fall IS followed down.
        let followed = filter(iob: 3.0).smooth(series(vals))[0].smoothed!
        XCTAssertGreaterThan(damped, 52.0) // held well above the 40 floor
        XCTAssertGreaterThan(damped, followed + 5.0) // and clearly higher than the un-gated case
    }
}
