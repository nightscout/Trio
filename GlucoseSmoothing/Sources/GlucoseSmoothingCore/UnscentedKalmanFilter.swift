import Foundation

/// Unscented Kalman Filter glucose smoother — a faithful Swift port of AndroidAPS
/// `UnscentedKalmanFilterPlugin.kt` (Boost-AAPS-core `Boost-V7-shadow`, 2026-07).
///
/// A two-state UKF over `x = [G, Ġ]` (glucose level mg/dL and rate mg/dL/min) with a
/// constant-velocity + rate-decay process model, adaptive measurement noise learned online, an
/// IOB-gated compression-low guard, gap segmentation, and a Rauch–Tung–Striebel backward pass. The
/// forward filter serves the live path; the RTS pass refines past points for display/analysis.
///
/// The numeric core is pure `Double` math (no linear-algebra library — the matrix square root is an
/// analytical 2×2 Cholesky). Android-specific coupling is injected: IOB (for the compression gate)
/// and sensor-change (for the learning reset) are closures; both default to the fail-safe path
/// (compression gate off, no reset), which is exactly what a freshly-constructed filter uses.
///
/// One instance carries the learned state (`learnedR`, innovation windows, session counters) across
/// `smooth` calls — construct a fresh instance for a clean start. Not thread-safe by itself.
public final class UnscentedKalmanFilter {
    // MARK: Injected collaborators (default to the fail-safe path)

    /// Total IOB (units) for the compression-damping gate. Returns a large value (gate off) by
    /// default, matching the Kotlin `currentIobTotalU()` fail-safe when IOB is unavailable.
    private let iobProvider: () -> Double
    /// Whether the sensor changed since the last call — triggers a learning reset. Default: never.
    private let sensorChangedSinceLastCall: () -> Bool

    // MARK: UKF parameters (Van der Merwe scaled formulation)

    private let n = 2
    private let alpha = 0.1
    private let beta = 2.0
    private let kappa = 0.0
    private let lambda: Double
    private let gamma: Double
    private var wm: [Double]
    private var wc: [Double]

    // MARK: Fixed process noise (G variance, rate variance) per 5 min

    private let q: [Double] = [1.0, 0.0, 0.0, 0.35]

    // MARK: Measurement-noise constants (variance, mg/dL²)

    private let rInit = 25.0
    private let rMin = 16.0
    private let rMax = 225.0
    private let rEffMax = 400.0
    private let innovationWindow = 18

    // MARK: Outlier diagnostics (χ² 99.99% / 1 DOF, abs innovation)

    private let chiSquaredThreshold = 15.13
    private let outlierAbsolute = 65.0

    // MARK: IOB-gated compression-low damping

    private let compressionBgCeiling = 75.0
    private let compressionIobMaxU = 2.0
    private let compressionDropMgdl = 30.0
    private let compressionWindow = 5
    private let compressionR = 900.0
    private let maxConsecutiveCompression = 3

    // MARK: Covariance limits

    private let maxGlucoseVariance = 400.0
    private let maxRateVariance = 4.0

    // MARK: Innovation-based reset validation

    private let innovationResetThreshold = 12.0
    private let innovationValidationSamples = 15

    // MARK: Gap handling

    private let minorGapThreshold = 7.0
    private let majorGapThreshold = 60.0
    private let rateDecayTimeConstant = 30.0
    private let millisPerMinute = 60000.0

    private func rateDamp(_ dt: Double) -> Double { exp(-dt / rateDecayTimeConstant) }

    // MARK: Persistent (learned) state

    private var learnedR: Double
    /// Deques are stored newest-first (index 0 = most recent), matching Kotlin `ArrayDeque.addFirst`.
    private var innovations: [Double] = [] // normalized ν² / (P[0] + R)
    private var rawInnovationVariance: [Double] = [] // raw ν²
    private var predVarHistory: [Double] = [] // predicted variance P_pred[0]
    private var lastProcessedTimestamp: Int64 = 0
    private var sensorSessionId = 0
    private var sessionMeasurementCount: Int64 = 0
    private var sessionOutlierCount: Int64 = 0
    private var consecutiveOutliers = 0

    public init(
        iobProvider: @escaping () -> Double = { 99.0 },
        sensorChangedSinceLastCall: @escaping () -> Bool = { false }
    ) {
        self.iobProvider = iobProvider
        self.sensorChangedSinceLastCall = sensorChangedSinceLastCall
        lambda = alpha * alpha * (Double(n) + kappa) - Double(n)
        gamma = (Double(n) + lambda).squareRoot()
        // Sigma-point weights.
        var wmArr = [Double](repeating: 0, count: 2 * n + 1)
        var wcArr = [Double](repeating: 0, count: 2 * n + 1)
        wmArr[0] = lambda / (Double(n) + lambda)
        wcArr[0] = lambda / (Double(n) + lambda) + (1 - alpha * alpha + beta)
        let w = 1.0 / (2.0 * (Double(n) + lambda))
        for i in 1 ..< (2 * n + 1) { wmArr[i] = w; wcArr[i] = w }
        wm = wmArr
        wc = wcArr
        learnedR = rInit
    }

    // MARK: - Public API

    /// Smooth a **newest-first** list of readings, writing each element's `smoothed` (mg/dL, ≥39)
    /// and — on the newest point of each segment — `trendArrow`. Returns the mutated copy. Any
    /// internal error falls back to raw-copied smoothed values so a fault never blocks the caller.
    @discardableResult
    public func smooth(_ input: [InMemoryGlucoseValue]) -> [InMemoryGlucoseValue] {
        var data = input
        if data.isEmpty { return data }
        smoothInternal(&data)
        return data
    }

    // MARK: - Segmentation

    /// Split into segments at major gaps (>60 min), invalid spacing, or an error-code reading.
    /// `startIdx` is the newest point in the segment, `endIdx` the oldest. (Kotlin `findDataSegments`.)
    private func findDataSegments(_ data: [InMemoryGlucoseValue]) -> [(startIdx: Int, endIdx: Int)] {
        if data.count < 2 { return [] }
        var segments: [(Int, Int)] = []
        var segmentStart = 0
        for i in 0 ..< (data.count - 1) {
            let timeDiff = Double(data[i].timestamp - data[i + 1].timestamp) / millisPerMinute
            if !(timeDiff >= 2.0 && timeDiff <= majorGapThreshold) || data[i].value == 38.0 {
                if i - segmentStart >= 2 { segments.append((segmentStart, i)) }
                segmentStart = i + 1
            }
        }
        if data.count - segmentStart >= 2 { segments.append((segmentStart, data.count - 1)) }
        return segments
    }

    private func copyRawToSmoothed(_ data: inout [InMemoryGlucoseValue]) {
        for i in data.indices {
            data[i].smoothed = max(data[i].value, 39.0)
            data[i].trendArrow = .none
        }
    }

    // MARK: - Main pipeline

    private func smoothInternal(_ data: inout [InMemoryGlucoseValue]) {
        if shouldResetLearning(currentTimestamp: data[0].timestamp) { resetLearning() }

        // Same IOB for the whole window (as the Kotlin/tsunami guard did) — correct for the newest
        // reading that feeds dosing. Fail-safe: a large value disables the compression gate.
        let iobTotal = currentIobTotalU()

        let segments = findDataSegments(data)
        if segments.isEmpty {
            copyRawToSmoothed(&data)
            return
        }

        let previousTimestamp = lastProcessedTimestamp
        lastProcessedTimestamp = data[0].timestamp

        for segment in segments {
            processSegment(&data, startIdx: segment.startIdx, endIdx: segment.endIdx,
                           previousTimestamp: previousTimestamp, iobTotal: iobTotal)
        }

        // Fill any unprocessed point (one orphaned by gaps/invalid spacing into a run of <2, so it
        // joined no segment) with its floored raw value. DELIBERATE deviation from the Kotlin, which
        // checks `smoothed == 0.0` against a `Double? = null` default — a dead check that never fires,
        // leaving orphan points null (AAPS then falls back via `recalculated = smoothed ?: value`).
        // The reference Python V4UKF instead pre-fills every point to `max(value, 39)`; matching it
        // keeps L2 parity on gappy traces AND honours the `smoothed` contract (never nil on return),
        // so a Seam-1 consumer can't nil-crash. Points that DID process are non-nil and untouched.
        for i in data.indices where data[i].smoothed == nil {
            data[i].smoothed = max(data[i].value, 39.0)
            data[i].trendArrow = .none
        }
    }

    private func currentIobTotalU() -> Double { iobProvider() }

    // MARK: - Per-segment forward UKF + backward RTS

    private struct FilterState {
        let x: [Double]
        let p: [Double]
        let xPred: [Double]
        let pPred: [Double]
        let dt: Double
    }

    private func processSegment(
        _ data: inout [InMemoryGlucoseValue],
        startIdx: Int, endIdx: Int, previousTimestamp: Int64, iobTotal: Double
    ) {
        let segmentSize = endIdx - startIdx + 1
        if segmentSize < 2 {
            data[startIdx].smoothed = max(data[startIdx].value, 39.0)
            data[startIdx].trendArrow = .none
            return
        }

        // Initialize state from the oldest point in the segment.
        let initialGlucose = data[endIdx].value
        var initialRate = 0.0
        if endIdx > 0 {
            let dt = Double(data[endIdx - 1].timestamp - data[endIdx].timestamp) / millisPerMinute
            if dt >= 3.0, dt <= 7.0 {
                initialRate = (data[endIdx - 1].value - data[endIdx].value) / dt
                initialRate = min(max(initialRate, -4.0), 4.0)
            }
        }

        var x = [initialGlucose, initialRate]
        var p = [16.0, 0.0, 0.0, 1.0]
        var r = learnedR

        var forwardStates: [FilterState] = [] // newest-first (addFirst)
        var forwardResults = [Double](repeating: 0, count: segmentSize)
        forwardResults[segmentSize - 1] = x[0]

        var segmentNewMeasurements = 0
        var recentSigns: [Int] = [] // newest-first, cap 3
        var consecutiveCompression = 0
        var recentRaw: [Double] = [] // newest-first, cap compressionWindow

        // === FORWARD PASS ===
        var i = endIdx - 1
        while i >= startIdx {
            let dt = Double(data[i].timestamp - data[i + 1].timestamp) / millisPerMinute

            // Bridge minor within-segment gaps by decaying the rate.
            if dt > minorGapThreshold, dt <= majorGapThreshold { x[1] *= rateDamp(dt) }

            p[0] = min(max(p[0], 0.1), maxGlucoseVariance)
            p[3] = min(max(p[3], 0.001), maxRateVariance)

            let dtUsed = dt
            let (xPredBase, pPredBase) = predict(x: x, p: p, q: q, dt: dtUsed)

            let rawValue = data[i].value
            let z = data[i].value

            // Error-code readings (≤38): prediction-only, no measurement update.
            if rawValue <= 38.0 {
                let stateBefore = FilterState(x: x, p: p, xPred: xPredBase, pPred: pPredBase, dt: dtUsed)
                x[0] = xPredBase[0]; x[1] = xPredBase[1]
                p[0] = pPredBase[0]; p[1] = pPredBase[1]; p[2] = pPredBase[2]; p[3] = pPredBase[3]
                forwardResults[i - startIdx] = x[0]
                forwardStates.insert(stateBefore, at: 0)
                i -= 1
                continue
            }

            // Innovation stats (pre-inflation, gating only).
            let innovation = z - xPredBase[0]
            let innovationVarianceRaw = pPredBase[0] + r
            let stdRaw = innovationVarianceRaw.squareRoot()
            let normRaw = innovation / stdRaw
            let isNewData = data[i].timestamp > previousTimestamp

            // 2-of-3 same-sign gate for a real trend at >2σ.
            let sign: Int = normRaw > 0.0 ? 1 : (normRaw < 0.0 ? -1 : 0)
            if recentSigns.count == 3 { recentSigns.removeLast() }
            recentSigns.insert(abs(normRaw) > 2.0 ? sign : 0, at: 0)
            let sameSignCount = sign == 0 ? 0 : recentSigns.filter { $0 == sign }.count
            let qInflateAllowed = sameSignCount >= 2
            let absn = abs(normRaw)

            // IOB-gated compression-low suspicion (baseline is raw, computed before adding z).
            let recentMaxRaw = recentRaw.isEmpty ? z : recentRaw.max()!
            let compressionSuspect = z < compressionBgCeiling &&
                iobTotal < compressionIobMaxU &&
                (recentMaxRaw - z) > compressionDropMgdl &&
                consecutiveCompression < maxConsecutiveCompression
            if compressionSuspect { consecutiveCompression += 1 } else { consecutiveCompression = 0 }
            recentRaw.insert(z, at: 0)
            if recentRaw.count > compressionWindow { recentRaw.removeLast() }

            // Huber-like R inflation (a compression suspect is down-weighted heavily instead).
            let rScale = 1.0 + max(0.0, absn - 2.0)
            let rEff = compressionSuspect ? compressionR : min(r * rScale, min(r + 100.0, rEffMax))

            // Q inflation for real trends (suppressed for a compression suspect).
            let zScore = max(absn, 1.0)
            let qScale = (qInflateAllowed && !compressionSuspect) ? min(max(zScore, 1.0), 3.0) : 1.0
            var tempQ = q
            if qScale > 1.0 {
                tempQ[0] = q[0] * min(qScale, 2.0)
                tempQ[3] = q[3] * qScale
            }

            let (xPredEff, pPredEff): ([Double], [Double]) =
                qScale > 1.0 ? predict(x: x, p: p, q: tempQ, dt: dtUsed) : (xPredBase, pPredBase)

            let stateBefore = FilterState(x: x, p: p, xPred: xPredEff, pPred: pPredEff, dt: dtUsed)

            let innovationVarianceEff = pPredEff[0] + rEff
            let mahalSqEff = (innovation * innovation) / innovationVarianceEff

            predVarHistory.insert(pPredEff[0], at: 0)
            if predVarHistory.count > innovationWindow { predVarHistory.removeLast() }

            update(xPred: xPredEff, pPred: pPredEff, z: z, r: rEff, x: &x, p: &p)

            trackInnovation(innovation: innovation, innovationVariance: innovationVarianceEff)

            // Pause R learning during a real trend and on very large residuals.
            let skipRUpdate = qInflateAllowed || absn > 3.0
            if !skipRUpdate { r = adaptMeasurementNoise(currentR: r) }

            if isNewData {
                segmentNewMeasurements += 1
                sessionMeasurementCount += 1
                if mahalSqEff > chiSquaredThreshold || abs(innovation) > outlierAbsolute {
                    sessionOutlierCount += 1
                }
            }

            forwardResults[i - startIdx] = x[0]
            forwardStates.insert(stateBefore, at: 0)
            i -= 1
        }

        learnedR = r
        _ = segmentNewMeasurements

        // === BACKWARD SMOOTHING (RTS) ===
        var smoothedResults = forwardResults
        if segmentSize >= 3, !forwardStates.isEmpty {
            let maxSmoothSteps = min(segmentSize - 1, forwardStates.count)
            var xSmooth = [forwardResults[0], x[1]]
            for step in 1 ... maxSmoothSteps {
                let state = forwardStates[step - 1]
                let c = computeSmootherGain(p: state.p, pPred: state.pPred, dt: state.dt)
                let dx0 = xSmooth[0] - state.xPred[0]
                let dx1 = xSmooth[1] - state.xPred[1]
                xSmooth[0] = forwardResults[step] + c[0] * dx0 + c[1] * dx1
                xSmooth[1] = state.x[1] + c[2] * dx0 + c[3] * dx1
                smoothedResults[step] = xSmooth[0]
            }
        }

        for idx in startIdx ... endIdx {
            let resultIdx = idx - startIdx
            data[idx].smoothed = max(smoothedResults[resultIdx], 39.0)
            data[idx].trendArrow = idx == startIdx ? computeTrendArrow(x[1]) : .none
        }
    }

    // MARK: - Adaptive R

    private func trackInnovation(innovation: Double, innovationVariance: Double) {
        let normalizedSq = (innovation * innovation) / innovationVariance
        let rawSq = innovation * innovation
        innovations.insert(normalizedSq, at: 0)
        rawInnovationVariance.insert(rawSq, at: 0)
        if innovations.count > innovationWindow { innovations.removeLast() }
        if rawInnovationVariance.count > innovationWindow { rawInnovationVariance.removeLast() }
    }

    private func adaptMeasurementNoise(currentR: Double) -> Double {
        if innovations.count < 12 || predVarHistory.isEmpty { return currentR }

        func trimmedMean(_ v: [Double], trim: Double = 0.20) -> Double {
            if v.isEmpty { return 0.0 }
            let s = v.sorted()
            let k = min(Int(Double(s.count) * trim), (s.count - 1) / 2)
            let core = s[k ..< (s.count - k)]
            return core.reduce(0, +) / Double(core.count)
        }

        let nSize = innovations.count
        let mRaw = trimmedMean(Array(rawInnovationVariance.prefix(nSize)))
        let pyyMed = trimmedMean(Array(predVarHistory.prefix(nSize)))

        let rHatRaw = max(mRaw - pyyMed, rMin)
        let rHat = min(max(rHatRaw, rMin), rMax)

        let goingUp = rHat > currentR
        let k = goingUp ? 0.18 : 0.12
        let step = currentR + k * (rHat - currentR)

        let upCap = goingUp ? 1.20 : 1.00
        let dnCap = goingUp ? 1.00 : 0.90
        let clamped = min(max(min(max(step, currentR * dnCap), currentR * upCap), rMin), rMax)

        let eta = 0.25
        return (1.0 - eta) * currentR + eta * clamped
    }

    // MARK: - Trend arrow

    private func computeTrendArrow(_ rate: Double) -> TrendArrow {
        switch rate {
        case let r where r > 2.0: return .doubleUp
        case let r where r > 1.0: return .singleUp
        case let r where r > 0.5: return .fortyFiveUp
        case let r where r < -2.0: return .doubleDown
        case let r where r < -1.0: return .singleDown
        case let r where r < -0.5: return .fortyFiveDown
        default: return .flat
        }
    }

    // MARK: - UKF core

    /// RTS smoother gain `C = P · Fᵀ · P_pred⁻¹`, with `F = [[1, dt], [0, exp(-dt/τ)]]`.
    private func computeSmootherGain(p: [Double], pPred: [Double], dt: Double) -> [Double] {
        let damp = rateDamp(dt)
        let pfT00 = p[0] + p[1] * dt
        let pfT01 = p[1] * damp
        let pfT10 = p[2] + p[3] * dt
        let pfT11 = p[3] * damp
        let det = pPred[0] * pPred[3] - pPred[1] * pPred[2]
        if abs(det) < 1e-10 { return [0, 0, 0, 0] }
        let inv00 = pPred[3] / det
        let inv01 = -pPred[1] / det
        let inv10 = -pPred[2] / det
        let inv11 = pPred[0] / det
        return [
            pfT00 * inv00 + pfT01 * inv10,
            pfT00 * inv01 + pfT01 * inv11,
            pfT10 * inv00 + pfT11 * inv10,
            pfT10 * inv01 + pfT11 * inv11,
        ]
    }

    /// Predict step: propagate sigma points through `f(x)=[G+Ġ·dt, Ġ·exp(-dt/τ)]`, add Q scaled by dt/5.
    private func predict(x: [Double], p: [Double], q: [Double], dt: Double) -> ([Double], [Double]) {
        let sigmaPoints = generateSigmaPoints(x: x, p: p)
        let damp = rateDamp(dt)
        var sigmaPointsPred = [[Double]](repeating: [0, 0], count: 2 * n + 1)
        for i in 0 ..< (2 * n + 1) {
            sigmaPointsPred[i][0] = sigmaPoints[i][0] + sigmaPoints[i][1] * dt
            sigmaPointsPred[i][1] = sigmaPoints[i][1] * damp
        }
        var xPred = [0.0, 0.0]
        for i in 0 ..< (2 * n + 1) {
            xPred[0] += wm[i] * sigmaPointsPred[i][0]
            xPred[1] += wm[i] * sigmaPointsPred[i][1]
        }
        var pPred = [0.0, 0.0, 0.0, 0.0]
        for i in 0 ..< (2 * n + 1) {
            let dx0 = sigmaPointsPred[i][0] - xPred[0]
            let dx1 = sigmaPointsPred[i][1] - xPred[1]
            pPred[0] += wc[i] * dx0 * dx0
            pPred[1] += wc[i] * dx0 * dx1
            pPred[2] += wc[i] * dx1 * dx0
            pPred[3] += wc[i] * dx1 * dx1
        }
        let qScale = dt / 5.0
        pPred[0] += q[0] * qScale
        pPred[3] += q[3] * qScale
        pPred[0] = max(pPred[0], 0.1)
        pPred[3] = max(pPred[3], 0.001)
        return (xPred, pPred)
    }

    /// Update step: measurement `h(x)=G`; Kalman gain; state + covariance update; rate clamped ±4.
    private func update(xPred: [Double], pPred: [Double], z: Double, r: Double, x: inout [Double], p: inout [Double]) {
        let sigmaPoints = generateSigmaPoints(x: xPred, p: pPred)
        var zSigma = [Double](repeating: 0, count: 2 * n + 1)
        for i in 0 ..< (2 * n + 1) { zSigma[i] = sigmaPoints[i][0] }

        var zPred = 0.0
        for i in 0 ..< (2 * n + 1) { zPred += wm[i] * zSigma[i] }

        var pzz = 0.0
        for i in 0 ..< (2 * n + 1) {
            let dz = zSigma[i] - zPred
            pzz += wc[i] * dz * dz
        }
        pzz += r

        if pzz < 1e-6 {
            x[0] = xPred[0]; x[1] = xPred[1]
            p[0] = pPred[0]; p[1] = pPred[1]; p[2] = pPred[2]; p[3] = pPred[3]
            return
        }

        var pxz = [0.0, 0.0]
        for i in 0 ..< (2 * n + 1) {
            let dx0 = sigmaPoints[i][0] - xPred[0]
            let dx1 = sigmaPoints[i][1] - xPred[1]
            let dz = zSigma[i] - zPred
            pxz[0] += wc[i] * dx0 * dz
            pxz[1] += wc[i] * dx1 * dz
        }

        let k = [pxz[0] / pzz, pxz[1] / pzz]
        let innovation = z - zPred
        x[0] = xPred[0] + k[0] * innovation
        x[1] = xPred[1] + k[1] * innovation
        x[1] = min(max(x[1], -4.0), 4.0)

        p[0] = pPred[0] - k[0] * pzz * k[0]
        p[1] = pPred[1] - k[0] * pzz * k[1]
        p[2] = pPred[2] - k[1] * pzz * k[0]
        p[3] = pPred[3] - k[1] * pzz * k[1]
        p[0] = max(p[0], 0.1)
        p[3] = max(p[3], 0.001)
    }

    /// Van der Merwe sigma points. `sqrtP` is column-major `[l11, l21, 0, l22]`; the Kotlin indexes
    /// it as two columns `col0=(l11,l21)`, `col1=(0,l22)` via `sqrtP[i*2+0]`, `sqrtP[i*2+1]`.
    private func generateSigmaPoints(x: [Double], p: [Double]) -> [[Double]] {
        var sigmaPoints = [[Double]](repeating: [0, 0], count: 2 * n + 1)
        let sqrtP = matrixSqrt2x2(p)
        sigmaPoints[0][0] = x[0]
        sigmaPoints[0][1] = x[1]
        for i in 0 ..< n {
            sigmaPoints[i + 1][0] = x[0] + gamma * sqrtP[i * 2 + 0]
            sigmaPoints[i + 1][1] = x[1] + gamma * sqrtP[i * 2 + 1]
            sigmaPoints[i + 1 + n][0] = x[0] - gamma * sqrtP[i * 2 + 0]
            sigmaPoints[i + 1 + n][1] = x[1] - gamma * sqrtP[i * 2 + 1]
        }
        return sigmaPoints
    }

    /// Analytical 2×2 Cholesky `L·Lᵀ = P` (symmetry enforced), returned column-major `[l11, l21, 0, l22]`.
    private func matrixSqrt2x2(_ p: [Double]) -> [Double] {
        let a = p[0]
        let b = (p[1] + p[2]) / 2.0
        let d = p[3]
        let l11 = max(a, 1e-9).squareRoot()
        let l21 = b / l11
        let discriminant = d - l21 * l21
        if discriminant < -1e-9 {
            return [max(a, 0.1).squareRoot(), 0.0, 0.0, max(d, 0.01).squareRoot()]
        }
        let l22 = max(discriminant, 1e-9).squareRoot()
        return [l11, l21, 0.0, l22]
    }

    // MARK: - Learning reset

    private func shouldResetLearning(currentTimestamp: Int64) -> Bool {
        if sensorChangedSinceLastCall() { return true }
        if lastProcessedTimestamp == 0 { return true }
        let timeDiffMinutes = Double(currentTimestamp - lastProcessedTimestamp) / millisPerMinute
        if timeDiffMinutes < 0 { return true }
        if timeDiffMinutes > 1440.0 { return true }
        if innovations.count >= innovationValidationSamples {
            let avgInnovation = innovations.reduce(0, +) / Double(innovations.count)
            if avgInnovation > innovationResetThreshold { return true }
        }
        return false
    }

    private func resetLearning() {
        learnedR = rInit
        innovations.removeAll()
        rawInnovationVariance.removeAll()
        predVarHistory.removeAll()
        sensorSessionId += 1
        sessionMeasurementCount = 0
        sessionOutlierCount = 0
        consecutiveOutliers = 0
    }
}
