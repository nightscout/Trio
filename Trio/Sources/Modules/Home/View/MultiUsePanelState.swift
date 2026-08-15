import Foundation

/// Content states of the Home multi-use panel; highest priority wins.
enum MultiUsePanelState: Equatable {
    case notificationsDisabled
    case pumpTimeMismatch
    case cgmStale
    case maxIOBZero
    case stats

    /// readings older than this offer manual glucose entry
    static let cgmStaleAfter: TimeInterval = 12 * 60

    static func resolve(
        notificationsDisabled: Bool,
        pumpTimeMismatch: Bool,
        lastGlucoseDate: Date?,
        maxIOB: Decimal,
        now: Date
    ) -> MultiUsePanelState {
        if notificationsDisabled { return .notificationsDisabled }
        if pumpTimeMismatch { return .pumpTimeMismatch }
        if now.timeIntervalSince(lastGlucoseDate ?? .distantPast) > cgmStaleAfter { return .cgmStale }
        if maxIOB <= 0 { return .maxIOBZero }
        return .stats
    }
}
