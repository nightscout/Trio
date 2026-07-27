import Foundation

/// Trend arrow derived from the filter's rate estimate. Mirrors AndroidAPS `TrendArrow`
/// (`core/data/.../TrendArrow.kt`) for the values the UKF emits.
public enum TrendArrow: String, Codable, Equatable, Sendable {
    case none
    case doubleUp
    case singleUp
    case fortyFiveUp
    case flat
    case fortyFiveDown
    case singleDown
    case doubleDown
}

/// One CGM reading as the smoother sees it — the Swift equivalent of AndroidAPS
/// `InMemoryGlucoseValue` (`core/data/.../iob/InMemoryGlucoseValue.kt`), reduced to the fields the
/// UKF reads (`timestamp`, `value`) and writes (`smoothed`, `trendArrow`).
///
/// `smooth()` is handed data **newest-first** — index 0 is the most recent reading, timestamps
/// descending — exactly as AndroidAPS hands its bucketed 5-min data to `Smoothing.smooth`.
public struct InMemoryGlucoseValue: Equatable, Sendable {
    /// Epoch milliseconds.
    public var timestamp: Int64
    /// Raw glucose reading, mg/dL.
    public var value: Double
    /// Output: trend arrow, set on the newest point of each segment from the filtered rate.
    public var trendArrow: TrendArrow
    /// Output: smoothed glucose, mg/dL. `nil` until the smoother writes it.
    public var smoothed: Double?

    public init(timestamp: Int64, value: Double, trendArrow: TrendArrow = .none, smoothed: Double? = nil) {
        self.timestamp = timestamp
        self.value = value
        self.trendArrow = trendArrow
        self.smoothed = smoothed
    }
}
