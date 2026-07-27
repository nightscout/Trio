import Foundation

/// AndroidAPS-faithful 5-minute bucketing, applied to the smoother's input in the production path.
///
/// AAPS feeds its UKF **bucketed** data (`AutosensDataStoreObject.createBucketedData`), not raw
/// readings. Trio originally smoothed raw readings (a deliberate divergence), which exposed a glitch:
/// two CGM readings spaced `< 2 min` apart (a backfill/catch-up) trip `findDataSegments`' segment
/// break, so the smoother re-initialises from the raw value and the line spikes. Bucketing regularises
/// the timestamps onto a 5-minute grid before smoothing, which removes that class of glitch and
/// restores parity with AAPS's production behaviour.
///
/// This is a **pure preprocessing step** — the `UnscentedKalmanFilter` core is unchanged, so its
/// per-call golden-vector / Python-parity tests still hold. All lists here are **newest-first**
/// (index 0 = most recent), matching the smoother and the AAPS `bgReadings` order.
///
/// Ported from `Boost-AAPS-core` `AutosensDataStoreObject.kt`: `isAbout5minData`,
/// `createBucketedData5min`, `createBucketedDataRecalculated`.
public enum GlucoseBucketing {
    private static let msMin: Int64 = 60000
    private static let msFive: Int64 = 5 * 60000
    private static let irregularDataMs: Int64 = 30000 // IRREGULAR_DATA_SEC = 30
    private static let twoThirtyMs: Int64 = 2 * 60000 + 30000

    /// AAPS dispatcher: `isAbout5minData` picks the 5-min bucketer, otherwise the recalculated
    /// resampler; the 5-min bucketer itself falls back to recalculated if its grid snap is too large.
    /// Fewer than 3 readings are returned unchanged (the smoother floors/copies them).
    public static func bucketed(_ bg: [InMemoryGlucoseValue]) -> [InMemoryGlucoseValue] {
        if bg.count < 3 { return bg }
        if isAbout5minData(bg) {
            if let fiveMin = createBucketedData5min(bg) { return fiveMin }
            return createBucketedDataRecalculated(bg)
        }
        return createBucketedDataRecalculated(bg)
    }

    /// True when the readings already sit ~on a 5-minute grid (every gap within 30 s of a 5-min
    /// multiple). Mirrors AAPS `isAbout5minData`.
    public static func isAbout5minData(_ bg: [InMemoryGlucoseValue]) -> Bool {
        if bg.count < 3 { return true }
        var totalDiff: Int64 = 0
        for i in 1 ..< bg.count {
            var diff = bg[i - 1].timestamp - bg[i].timestamp // newest-first → positive
            diff %= msFive
            if diff > twoThirtyMs { diff -= msFive }
            totalDiff += diff
            if abs(diff) > irregularDataMs { return false }
        }
        let averageDiffSec = totalDiff / Int64(bg.count) / 1000
        return averageDiffSec < 1
    }

    /// AAPS `createBucketedData5min`: average readings ≤2 min apart into the current bucket, open a new
    /// bucket for 2–8 min, interpolate 5-min fillers across >8-min gaps, then snap every bucket onto a
    /// clean 5-min grid. Returns `nil` if a snap needs > 90 s (AAPS then falls back to recalculated).
    public static func createBucketedData5min(_ bg: [InMemoryGlucoseValue]) -> [InMemoryGlucoseValue]? {
        if bg.count < 3 { return bg }
        var ts: [Int64] = [bg[0].timestamp]
        var vals: [Double] = [bg[0].value]
        var j = 0
        for i in 1 ..< bg.count {
            let bgTime = bg[i].timestamp
            var lastBgTime = bg[i - 1].timestamp
            let elapsed = (bgTime - lastBgTime) / msMin // integer, negative (newest-first)
            if abs(elapsed) > 8 {
                var lastBgValue = bg[i - 1].value
                var em = abs(elapsed)
                while em > 5 {
                    let nextBgTime = lastBgTime - msFive
                    j += 1
                    let gapDelta = bg[i].value - lastBgValue
                    let nextBg = lastBgValue + 5.0 / Double(em) * gapDelta
                    ts.append(nextBgTime)
                    vals.append(nextBg.rounded())
                    em -= 5
                    lastBgValue = nextBg
                    lastBgTime = nextBgTime
                }
                j += 1
                ts.append(bgTime)
                vals.append(bg[i].value)
            } else if abs(elapsed) > 2 {
                j += 1
                ts.append(bgTime)
                vals.append(bg[i].value)
            } else {
                vals[j] = (vals[j] + bg[i].value) / 2.0
            }
        }
        // Normalize onto the 5-min grid. Oldest keeps its time (referenceTime unset on a single pass).
        for i in stride(from: ts.count - 2, through: 0, by: -1) {
            let adjustedSec = ((ts[i] - ts[i + 1]) - msFive) / 1000
            if abs(adjustedSec) > 90 { return nil } // AAPS fallback → recalculated
            ts[i] = ts[i + 1] + msFive
        }
        return zip(ts, vals).map { InMemoryGlucoseValue(timestamp: $0.0, value: $0.1) }
    }

    /// AAPS `createBucketedDataRecalculated`: resample onto a strict 5-min grid (anchored at the newest
    /// reading, walking back) by linear interpolation between the raw readings bracketing each grid point.
    public static func createBucketedDataRecalculated(_ bg: [InMemoryGlucoseValue]) -> [InMemoryGlucoseValue] {
        if bg.count < 3 { return bg }
        var currentTime = bg[0].timestamp // referenceTime unset → adjustToReferenceTime is identity
        var out: [InMemoryGlucoseValue] = []
        func findNewer(_ t: Int64) -> InMemoryGlucoseValue? {
            var best: InMemoryGlucoseValue?
            for v in bg where v.timestamp >= t { if best == nil || v.timestamp < best!.timestamp { best = v } }
            return best
        }
        func findOlder(_ t: Int64) -> InMemoryGlucoseValue? {
            var best: InMemoryGlucoseValue?
            for v in bg where v.timestamp <= t { if best == nil || v.timestamp > best!.timestamp { best = v } }
            return best
        }
        while true {
            guard let newer = findNewer(currentTime), let older = findOlder(currentTime) else { break }
            if older.timestamp == newer.timestamp {
                out.append(InMemoryGlucoseValue(timestamp: currentTime, value: newer.value))
            } else {
                let bgDelta = newer.value - older.value
                let timeDiffToNew = Double(newer.timestamp - currentTime)
                let span = Double(newer.timestamp - older.timestamp)
                let currentBg = newer.value - timeDiffToNew / span * bgDelta
                out.append(InMemoryGlucoseValue(timestamp: currentTime, value: currentBg.rounded()))
            }
            currentTime -= msFive
        }
        return out
    }

    /// Project a smoothed **grid** (newest-first, `.smoothed` set) back onto an original reading's
    /// timestamp by linear interpolation between the two bracketing grid points (clamped at the ends).
    /// This is the Trio-specific write-back: AAPS displays bucketed data directly, but Trio stores
    /// `smoothedGlucose` per `GlucoseStored` row, so each raw row samples the smoothed grid at its time.
    public static func interpolatedSmoothed(at timestamp: Int64, grid: [InMemoryGlucoseValue]) -> Double? {
        guard !grid.isEmpty else { return nil }
        if timestamp >= grid[0].timestamp { return grid[0].smoothed } // newer than newest grid point
        if let last = grid.last, timestamp <= last.timestamp { return last.smoothed } // older than oldest
        // grid is newest-first (descending timestamp): find i with grid[i] >= ts >= grid[i+1].
        for i in 0 ..< (grid.count - 1) {
            let newer = grid[i], older = grid[i + 1]
            if timestamp <= newer.timestamp, timestamp >= older.timestamp {
                guard let sNewer = newer.smoothed, let sOlder = older.smoothed else { return newer.smoothed ?? older.smoothed }
                let span = Double(newer.timestamp - older.timestamp)
                if span <= 0 { return sNewer }
                let frac = Double(timestamp - older.timestamp) / span
                return sOlder + (sNewer - sOlder) * frac
            }
        }
        return grid[0].smoothed
    }
}
