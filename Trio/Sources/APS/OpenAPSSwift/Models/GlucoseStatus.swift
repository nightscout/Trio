import Foundation

/// Represents the computed status of the most recent CGM reading,
/// including delta‐rates over various time windows for our
/// swift-based Oref`DeterminationGenerator`.
public struct GlucoseStatus: Codable {
    /// Immediate delta (mg/dL per 5 m) over the last ~5 m
    public let delta: Decimal
    /// The (“smoothed”) current glucose value (mg/dL)
    public let glucose: Decimal
    /// Sensor noise level
    public let noise: Int
    /// Average delta (mg/dL per 5 m) over ~5–15 m ago
    public let shortAvgDelta: Decimal
    /// Average delta (mg/dL per 5 m) over ~20–40 m ago
    public let longAvgDelta: Decimal
    /// Timestamp of the “now” reading
    public let date: Date
    /// Index of the last “cal” record (if any)
    public let lastCalIndex: Int?
    /// The original device/type string (e.g. “sgv” or “cal”)
    public let device: String?

    /// helper function to calculate the maxDelta variable from JS
    public var maxDelta: Decimal {
        max(delta, shortAvgDelta, longAvgDelta)
    }
}
