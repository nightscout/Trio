# Adaptive Smoothing (`GlucoseSmoothingCore`)

A standalone, dependency-free Swift package that provides Trio's **Adaptive Smoothing** CGM
glucose smoother. It is the sole smoother (it replaced the previous double-exponential one) and is
enabled by the *Settings → CGM → Smooth Glucose Value* toggle. **Off by default**: with the toggle
off, nothing here runs and behaviour is byte-identical to today.

Despite the class name, this is **much more than a Kalman filter**. At its core is an Unscented
Kalman Filter, but the useful behaviour comes from the layers built around it: online noise
learning, physiological outlier/compression handling, gap-aware segmentation, and a backward
refinement pass. "Adaptive Smoothing" is the umbrella name for that whole engine.

## What it actually does

It estimates **both the glucose level and its rate of change** — `x = [G, Ġ]` (mg/dL and
mg/dL·min⁻¹) — rather than just smoothing the level. That rate estimate is what lets it track real
trends with less lag while still rejecting noise, and it produces a trend arrow as a by-product.

**1. Unscented state estimation (the core).** A constant-velocity model with rate decay
(`Ġ ← Ġ·exp(−dt/30)`) is propagated through Van der Merwe sigma points (α=0.1, β=2, κ=0) so the
nonlinearity is handled without linearisation. The 2×2 matrix square root is an analytical Cholesky —
**no linear-algebra dependency**.

**2. Online-learned measurement noise — the "adaptive" part.** Instead of a fixed noise constant,
the filter estimates *this sensor's* actual noise from its own innovations (a trimmed-mean estimate
over a rolling window), and eases toward it with asymmetric rate limits. A quiet sensor gets trusted
more; a noisy one gets smoothed harder — automatically, without user tuning.

**3. Huber-style outlier rejection.** A reading landing far outside the filter's own predicted
uncertainty (>2σ) has its measurement noise inflated in proportion, so an isolated spike barely moves
the estimate (a lone `300` among `100`s is pulled well below `200`).

**4. Real-trend detection.** A 2-of-3 same-sign, >2σ gate distinguishes a genuine fast move from
noise and *inflates process noise* so the filter accelerates onto the new trend instead of lagging —
the opposite response to an outlier.

**5. IOB-gated compression-low guard.** When glucose is low (<75 mg/dL), there's little insulin on
board (IOB < 2U), and the drop is steep (>30 mg/dL from the recent baseline), the dip is treated as a
probable sensor-compression artefact ("lying on the sensor") and heavily down-weighted rather than
tracked to the floor — but only when low IOB makes a real fall unlikely, and capped at 3 consecutive
readings so a genuine low is never masked for long. Requires an IOB provider; **off by default** (a
freshly-constructed filter fails safe with the gate disabled).

**6. Gap-aware segmentation.** The series is split at >60-min gaps, invalid spacing, and error-code
readings (≤38, which are prediction-only); minor 7–60-min gaps are bridged by decaying the rate
across them.

**7. Rauch–Tung–Striebel backward pass.** The forward filter serves the live/dosing path (the newest
point); the RTS pass refines *past* points for the chart and analysis.

**8. Fail-safe throughout.** Any degenerate case copies the raw value (floored at 39 mg/dL); every
returned point is non-nil and ≥39, so a consumer can never nil-crash.

## Faithfulness

`UnscentedKalmanFilter` is a 1:1 Swift port of AndroidAPS `UnscentedKalmanFilterPlugin.kt`
(Boost-AAPS-core `Boost-V7-shadow`), validated **bit-exact** against a reference Python
implementation (`Tests/.../UkfPythonParityTests`) and against 9 golden vectors mirroring the shipped
Kotlin unit test. The one graft on top of mainline AAPS is the IOB-gated compression guard, which is
default-off.

## Use

```swift
import GlucoseSmoothingCore

// Default: compression gate off (no IOB wired), no sensor-change reset — the fail-safe path.
let engine = UnscentedKalmanFilter()
let smoothed = engine.smooth(readings)   // readings NEWEST-FIRST; each .smoothed (≥39) + .trendArrow set

// Wire real collaborators to enable the compression guard / learning reset:
let engine = UnscentedKalmanFilter(
    iobProvider: { currentIOB },                    // enables the compression-low guard
    sensorChangedSinceLastCall: { sensorSwapped }   // resets learned noise on sensor change
)
```

> **Ordering matters.** `smooth()` requires **newest-first** input (`data[0]` = most recent). Fed
> oldest-first, segmentation sees negative time-diffs, forms no segment, and copies raw — the engine
> goes inert. In Trio, `fetchGlucose` returns readings *oldest-first*, so
> `FetchGlucoseManager.applyAdaptiveSmoothingAndStore` reverses before feeding the engine.
> `UkfOrderingRegressionTest` guards this.

## How Trio uses it

When smoothing is enabled, `FetchGlucoseManager.applyAdaptiveSmoothingAndStore` runs the engine and
writes `smoothedGlucose`. It fail-safes internally (floors at 39, fills unmodellable points with the
raw value), so there's no separate fallback pass. `smoothedGlucose` feeds oref (when smoothing is on) and the
chart's smoothed line; the primary glucose number and dots always remain the **raw** reading.

## Test

```
cd GlucoseSmoothing && swift test
```

Golden vectors + Python parity, both green.

## Scope

This is a **sensing** improvement — a better estimate of the glucose signal and its rate, with less
lag and less jitter than exponential smoothing. It makes **no dosing, time-in-range, or glycaemic
outcome claim**; retrospective data cannot supply the counterfactual trajectory. `None` and
`Exponential` remain available.
