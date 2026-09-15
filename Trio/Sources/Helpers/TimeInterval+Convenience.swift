import Foundation

/// Convenience constructors + getters used across the app for `TimeInterval`
/// math at minute/hour granularity. Previously lived inside the deleted
/// `Snooze` module; broken out here because real callers exist outside the
/// alert pipeline (chart markers, pump-history windows, fetch timers, etc.).
extension TimeInterval {
    static func seconds(_ seconds: Double) -> TimeInterval { seconds }

    static func minutes(_ minutes: Double) -> TimeInterval {
        TimeInterval(minutes: minutes)
    }

    static func hours(_ hours: Double) -> TimeInterval {
        TimeInterval(minutes: hours * 60)
    }

    init(minutes: Double) {
        self.init(minutes * 60)
    }

    init(hours: Double) {
        self.init(minutes: hours * 60)
    }

    var minutes: Double { self / 60.0 }

    var hours: Double { minutes / 60.0 }
}
