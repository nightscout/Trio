import CoreData
import Foundation
import Testing

@testable import Trio

/// Regression guard for the UKF glucose-smoother ORDER bug.
///
/// `fetchGlucose` returns readings **oldest-first** (it fetches date-descending for the limit, then
/// reverses). `UnscentedKalmanFilter.smooth` requires **newest-first** — fed oldest-first its
/// segmentation sees negative time-diffs, forms no segment, and copies raw, so the filter goes inert.
/// `applyAdaptiveSmoothingAndStore` must therefore reverse before feeding the UKF core.
///
/// This test feeds the production method the production order (oldest-first) and asserts (a) the UKF
/// actually smooths (departs from raw) and (b) the stored values match an independent newest-first
/// UKF run. If the reversal is ever removed, both assertions fail.
@Suite("UKF ordering regression", .serialized) struct UkfOrderingRegressionTest {
    @Test(
        "applyAdaptiveSmoothingAndStore feeds the UKF core newest-first (guards the oldest-first order bug)"
    ) func adaptiveSmoothingReceivesNewestFirst(
    ) async throws {
        let stack = try await CoreDataStack.createForTests()
        let ctx = stack.newTaskContext()

        // A deliberately noisy series so a working UKF visibly departs from raw. Built OLDEST-first
        // (index 0 = oldest), 5-min spacing — exactly the order fetchGlucose hands the smoothers.
        let sgvs: [Int16] = [100, 132, 94, 136, 90, 140, 92, 138, 96, 134, 98, 130, 101, 128, 103]
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let (storedOldestFirst, oracleOldestFirst, raws): ([Double], [Double], [Double]) =
            try await ctx.perform {
                var readings: [GlucoseStored] = []
                for (i, v) in sgvs.enumerated() {
                    let g = GlucoseStored(context: ctx)
                    g.date = base.addingTimeInterval(Double(i) * 300) // increasing dates → oldest-first
                    g.glucose = v
                    g.smoothedGlucose = nil
                    g.isManual = false
                    g.id = UUID()
                    readings.append(g)
                }
                try ctx.save()
                let n = readings.count

                // Production method — receives oldest-first, must reverse internally. Reset the
                // persistent smoother first so this single call is a clean start, matching the fresh
                // oracle below.
                BaseFetchGlucoseManager.resetSharedSmoother()
                BaseFetchGlucoseManager.applyAdaptiveSmoothingAndStore(glucoseReadings: readings)
                let stored = readings.map { $0.smoothedGlucose?.doubleValue ?? -1 } // oldest-first

                // Independent oracle: feed the UKF newest-first directly, then map back to oldest-first
                // with the same round-to-integer + 39 floor the production method applies.
                let newestFirst = readings.reversed().map {
                    InMemoryGlucoseValue(
                        timestamp: Int64($0.date!.timeIntervalSince1970 * 1000),
                        value: Double($0.glucose)
                    )
                }
                let out = UnscentedKalmanFilter().smooth(newestFirst) // newest-first
                var oracle = [Double](repeating: -1, count: n)
                for k in out.indices where out[k].smoothed != nil {
                    let v = max(Decimal(out[k].smoothed!).rounded(toPlaces: 0), 39)
                    oracle[n - 1 - k] = (v as NSDecimalNumber).doubleValue // out[k] ↔ readings[n-1-k]
                }
                return (stored, oracle, readings.map { Double($0.glucose) })
            }

        // (a) Smoothing actually happened. Fed backwards, every stored value equals raw and this is 0.
        let departures = zip(storedOldestFirst, raws).filter { abs($0 - $1) > 2.0 }.count
        #expect(
            departures >= sgvs.count / 2,
            "UKF barely departed from raw (\(departures)/\(sgvs.count)) — likely fed oldest-first (order bug)"
        )

        // (b) Stored values match the newest-first UKF oracle (± rounding).
        for (i, (s, o)) in zip(storedOldestFirst, oracleOldestFirst).enumerated() {
            #expect(abs(s - o) <= 1.0, "reading \(i): stored \(s) but newest-first UKF gives \(o) — ordering mismatch")
        }
    }
}
