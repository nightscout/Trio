import Foundation

/// Home's clock-driven representation of a real Libre sensor warmup.
///
/// The manager's published warmup flag advances when a sensor packet arrives.
/// Keeping the authoritative activation date here lets the Home ring advance
/// continuously and leave warmup exactly at the 60-minute boundary.
struct LibreWarmupDisplayState: Equatable {
    let activatedAt: Date
    let endsAt: Date

    init(activatedAt: Date, duration: TimeInterval) {
        self.activatedAt = activatedAt
        endsAt = activatedAt.addingTimeInterval(duration)
    }

    func isActive(at date: Date) -> Bool {
        date >= activatedAt && date < endsAt
    }

    func progress(at date: Date) -> Double {
        let duration = endsAt.timeIntervalSince(activatedAt)
        guard duration > 0 else { return 1 }
        return min(max(date.timeIntervalSince(activatedAt) / duration, 0), 1)
    }
}

/// Compact `5d 14h` / `22h` / `45m` remaining-time formatter. Used as a
/// fallback tag label when the CGM doesn't surface a `cgmStatusHighlight`
/// but the lifecycle progress lets us derive an expiration date.
enum SensorRemainingTimeFormatter {
    static func format(until expiresAt: Date, now: Date = Date()) -> String {
        let remaining = max(0, expiresAt.timeIntervalSince(now))
        let totalMinutes = Int(remaining) / 60
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        let d = String(localized: "d", comment: "Abbreviation for Days")
        let h = String(localized: "h", comment: "Abbreviation for Hours")
        let m = String(localized: "m", comment: "Abbreviation for Minutes")
        if days > 0, hours > 0 { return "\(days)\(d) \(hours)\(h)" }
        if days > 0 { return "\(days)\(d)" }
        if hours > 0 { return "\(hours)\(h)" }
        if minutes > 0 { return "\(minutes)\(m)" }
        return "<" + "\u{00A0}" + "1" + "\u{00A0}" + m
    }
}
