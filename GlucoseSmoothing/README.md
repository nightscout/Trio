# GlucoseSmoothingCore

A standalone, dependency-free Swift package for CGM glucose smoothing — starting with an
**Unscented Kalman Filter (UKF)** smoother, a level-**and**-rate estimator intended to replace
Trio's double-exponential smoother.

This is **P0** of the [UKF development & test plan](https://claude.ai/code/artifact/1c3f906b-421b-475c-9003-14f94650fe2e):
the filter ported as pure Swift, with the golden-vector correctness gate. App wiring (Seam 1 in
`FetchGlucoseManager`, a `glucoseSmoother` setting) and the benchmark/replay suites land in later
phases.

## What it is

`UnscentedKalmanFilter` is a faithful Swift port of AndroidAPS
`UnscentedKalmanFilterPlugin.kt` (Boost-AAPS-core, `Boost-V7-shadow`, 2026-07). A two-state UKF over
`x = [G, Ġ]` (glucose level mg/dL, rate mg/dL/min):

- constant-velocity process model with rate decay (`Ġ ← Ġ·exp(−dt/30)`);
- Van der Merwe scaled sigma points (α=0.1, β=2, κ=0) via an analytical 2×2 Cholesky — **no
  linear-algebra library**;
- measurement noise **learned online** (trimmed-mean innovation-based estimation) with Huber-style
  R-inflation that soft-rejects outliers in proportion to the filter's own uncertainty;
- an **IOB-gated compression-low guard** (a suspected compression dip is heavily down-weighted, not
  tracked to the floor);
- **gap segmentation** (splits at >60-min gaps, bridges 7–60-min gaps, error-code readings ≤38 are
  prediction-only);
- a **Rauch–Tung–Striebel backward pass** — the forward filter serves the live path, the RTS pass
  refines past points for display/analysis.

Android coupling is injected and defaults to the fail-safe path:

```swift
// Compression gate off (IOB unavailable → large value), no sensor-change reset — the defaults a
// freshly-constructed filter uses, and what the golden vectors exercise.
let ukf = UnscentedKalmanFilter()
let smoothed = ukf.smooth(readings)   // readings NEWEST-FIRST; each .smoothed (≥39) + .trendArrow set

// Wire the real collaborators later (P1+):
let ukf = UnscentedKalmanFilter(
    iobProvider: { currentIOB },                    // enables the compression gate
    sensorChangedSinceLastCall: { sensorSwapped }   // enables the learning reset on sensor change
)
```

## Test

```
cd GlucoseSmoothing && swift test
```

`UkfGoldenVectorTests` is the correctness gate: the 9 behaviours the shipped AndroidAPS Kotlin unit
test asserts, same input vectors and thresholds (empty→empty, single-value floor at 39, error-code
collapse, clean-series sanity, rising trend, isolated-spike damping, major-gap segmentation,
determinism to 1e-9, IOB-gated compression low). The reference Python benchmark aborts unless its
UKF passes the same 9; this port must too.

## Scope

This is a **sensing** improvement — a better estimate of the glucose signal and its rate, with less
lag and less jitter than exponential smoothing. It makes **no dosing, time-in-range or glycaemic
outcome claim**; retrospective data cannot give the counterfactual trajectory. No-smoothing remains
the simple fallback.
