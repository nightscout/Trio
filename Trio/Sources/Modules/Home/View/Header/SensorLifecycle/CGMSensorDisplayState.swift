import Foundation

/// Compact `5d 14h` / `22h` / `45m` remaining-time formatter. Used as a
/// fallback tag label when the CGM doesn't surface a `cgmStatusHighlight`
/// but the lifecycle progress lets us derive an expiration date.
enum SensorRemainingTimeFormatter {
    static func format(until expiresAt: Date, now: Date = Date()) -> String {
        let remaining = max(0, expiresAt.timeIntervalSince(now))
        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0, hours > 0 { return "\(days)d \(hours)h" }
        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
