import Foundation

/// A volatility-adaptive Kalman filter for CGM signal processing.
///
/// State vector: [BG level, BG velocity (mg/dL per min), BG acceleration (mg/dL per min²)]
///
/// The process noise covariance adapts based on recent BG dynamics:
/// - During stable BG periods: aggressive smoothing, clean derivatives
/// - During fast meal-driven rises: tracks the signal, preserves acceleration for meal detection
///
/// Per the oref improvements spec (§9.2), this replaces the Savitzky-Golay filter with a
/// proper state-space estimator that outputs smoothed BG, velocity, acceleration, and
/// uncertainty estimates for each.
final class AdaptiveKalmanFilter {
    // MARK: - Configuration

    struct Config {
        /// Baseline process noise for BG level (mg/dL²). Low = aggressive smoothing at rest.
        var qBaseBG: Double = 0.5

        /// Baseline process noise for velocity ((mg/dL/min)²)
        var qBaseVelocity: Double = 0.02

        /// Baseline process noise for acceleration ((mg/dL/min²)²)
        var qBaseAcceleration: Double = 0.005

        /// Volatility scaling coefficient. Higher = filter tracks faster during dynamic periods.
        var volatilityScale: Double = 0.8

        /// CGM measurement noise variance (mg/dL²). Typical CGM noise is ~5-10 mg/dL SD.
        var measurementNoise: Double = 36.0

        /// Time step between CGM readings in minutes
        var dt: Double = 5.0

        /// EMA alpha for tracking recent absolute velocity (used for adaptive Q)
        var velocityEMAAlpha: Double = 0.4
    }

    // MARK: - State

    struct State {
        /// Smoothed BG level (mg/dL)
        var bg: Double

        /// BG velocity (mg/dL per minute, positive = rising)
        var velocity: Double

        /// BG acceleration (mg/dL per minute², positive = accelerating upward)
        var acceleration: Double

        /// Estimation error covariance matrix (3x3, stored as flat array row-major)
        var P: [Double]

        /// Timestamp of last update
        var timestamp: Date

        /// EMA of recent absolute velocity (for adaptive process noise)
        var recentAbsVelocity: Double
    }

    private(set) var state: State?
    private(set) var config: Config
    private var previousAcceleration: Double?

    /// Jerk (rate of change of acceleration) from the last two updates.
    /// Computed as (acceleration_new - acceleration_old) / dt.
    private(set) var jerk: Double?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    /// Process a new CGM reading. Returns the updated filter output.
    @discardableResult
    func update(glucose: Double, at timestamp: Date) -> FilterOutput {
        if let currentState = state {
            let dtMinutes = timestamp.timeIntervalSince(currentState.timestamp) / 60.0

            // Guard against nonsensical time gaps
            if dtMinutes <= 0 {
                return makeOutput()
            }

            // If gap is too large (>15 min, i.e. missed readings), widen uncertainty
            let effectiveDt = min(dtMinutes, 15.0)
            let gapFactor = dtMinutes > 7.5 ? dtMinutes / config.dt : 1.0

            predict(dt: effectiveDt, gapFactor: gapFactor)
            correct(measurement: glucose)

            state?.timestamp = timestamp
        } else {
            // Initialize state from first reading
            state = State(
                bg: glucose,
                velocity: 0,
                acceleration: 0,
                P: identityScaled(diag: [config.measurementNoise, 1.0, 0.1]),
                timestamp: timestamp,
                recentAbsVelocity: 0
            )
            previousAcceleration = nil
            jerk = nil
        }

        return makeOutput()
    }

    /// Reset the filter state (e.g. on sensor change)
    func reset() {
        state = nil
        previousAcceleration = nil
        jerk = nil
    }

    // MARK: - Kalman Predict Step

    private func predict(dt: Double, gapFactor: Double) {
        guard var s = state else { return }

        // State transition: x_new = F * x_old
        // BG = BG + velocity*dt + 0.5*acceleration*dt²
        // velocity = velocity + acceleration*dt
        // acceleration = acceleration (assumed constant between readings)
        let predictedBG = s.bg + s.velocity * dt + 0.5 * s.acceleration * dt * dt
        let predictedVelocity = s.velocity + s.acceleration * dt
        let predictedAcceleration = s.acceleration

        // State transition matrix F (3x3)
        let F: [Double] = [
            1, dt, 0.5 * dt * dt,
            0, 1, dt,
            0, 0, 1
        ]

        // Adaptive process noise: scale with recent velocity magnitude
        let adaptiveFactor = 1.0 + config.volatilityScale * s.recentAbsVelocity
        let gapScale = gapFactor // wider uncertainty for missed readings

        let q0 = config.qBaseBG * adaptiveFactor * gapScale
        let q1 = config.qBaseVelocity * adaptiveFactor * gapScale
        let q2 = config.qBaseAcceleration * adaptiveFactor * gapScale

        // Process noise Q (diagonal)
        let Q: [Double] = [
            q0, 0, 0,
            0, q1, 0,
            0, 0, q2
        ]

        // P_new = F * P * F^T + Q
        let FP = multiply3x3(F, s.P)
        let FT = transpose3x3(F)
        let FPFT = multiply3x3(FP, FT)
        s.P = add3x3(FPFT, Q)

        s.bg = predictedBG
        s.velocity = predictedVelocity
        s.acceleration = predictedAcceleration

        state = s
    }

    // MARK: - Kalman Correct Step

    private func correct(measurement: Double) {
        guard var s = state else { return }

        // Observation matrix H = [1, 0, 0] (we only observe BG directly)
        // Innovation: y = z - H*x = measurement - predicted_bg
        let innovation = measurement - s.bg

        // Innovation covariance: S = H*P*H^T + R = P[0,0] + R
        let S = s.P[0] + config.measurementNoise

        // Kalman gain: K = P*H^T / S = [P[0,0], P[1,0], P[2,0]] / S
        let K0 = s.P[0] / S // gain for BG
        let K1 = s.P[3] / S // gain for velocity
        let K2 = s.P[6] / S // gain for acceleration

        // Store previous acceleration for jerk calculation
        previousAcceleration = s.acceleration

        // Update state: x = x + K * innovation
        s.bg += K0 * innovation
        s.velocity += K1 * innovation
        s.acceleration += K2 * innovation

        // Compute jerk if we have previous acceleration
        if let prevAcc = previousAcceleration {
            jerk = (s.acceleration - prevAcc) / config.dt
        }

        // Update covariance: P = (I - K*H) * P
        // K*H is a 3x3 matrix where only column 0 is non-zero
        let KH: [Double] = [
            K0, 0, 0,
            K1, 0, 0,
            K2, 0, 0
        ]
        let I_KH = subtract3x3(identity3x3(), KH)
        s.P = multiply3x3(I_KH, s.P)

        // Update EMA of recent absolute velocity
        s.recentAbsVelocity = config.velocityEMAAlpha * abs(s.velocity) +
            (1 - config.velocityEMAAlpha) * s.recentAbsVelocity

        state = s
    }

    // MARK: - Output

    struct FilterOutput {
        /// Smoothed BG (mg/dL)
        let bg: Double

        /// BG velocity (mg/dL per minute)
        let velocity: Double

        /// BG acceleration (mg/dL per minute²)
        let acceleration: Double

        /// BG jerk (mg/dL per minute³), nil if insufficient data
        let jerk: Double?

        /// Uncertainty (standard deviation) of BG estimate
        let bgUncertainty: Double

        /// Uncertainty of velocity estimate
        let velocityUncertainty: Double

        /// Uncertainty of acceleration estimate
        let accelerationUncertainty: Double

        /// Timestamp of this estimate
        let timestamp: Date
    }

    private func makeOutput() -> FilterOutput {
        guard let s = state else {
            // Should not happen if called after update, but return safe defaults
            return FilterOutput(
                bg: 0, velocity: 0, acceleration: 0, jerk: nil,
                bgUncertainty: 0, velocityUncertainty: 0, accelerationUncertainty: 0,
                timestamp: Date()
            )
        }
        return FilterOutput(
            bg: s.bg,
            velocity: s.velocity,
            acceleration: s.acceleration,
            jerk: jerk,
            bgUncertainty: sqrt(max(s.P[0], 0)),
            velocityUncertainty: sqrt(max(s.P[4], 0)),
            accelerationUncertainty: sqrt(max(s.P[8], 0)),
            timestamp: s.timestamp
        )
    }

    // MARK: - 3x3 Matrix Operations (row-major flat arrays)

    private func identity3x3() -> [Double] {
        [1, 0, 0, 0, 1, 0, 0, 0, 1]
    }

    private func identityScaled(diag: [Double]) -> [Double] {
        [diag[0], 0, 0, 0, diag[1], 0, 0, 0, diag[2]]
    }

    private func multiply3x3(_ A: [Double], _ B: [Double]) -> [Double] {
        var C = [Double](repeating: 0, count: 9)
        for i in 0 ..< 3 {
            for j in 0 ..< 3 {
                for k in 0 ..< 3 {
                    C[i * 3 + j] += A[i * 3 + k] * B[k * 3 + j]
                }
            }
        }
        return C
    }

    private func transpose3x3(_ A: [Double]) -> [Double] {
        [A[0], A[3], A[6], A[1], A[4], A[7], A[2], A[5], A[8]]
    }

    private func add3x3(_ A: [Double], _ B: [Double]) -> [Double] {
        zip(A, B).map(+)
    }

    private func subtract3x3(_ A: [Double], _ B: [Double]) -> [Double] {
        zip(A, B).map(-)
    }
}
