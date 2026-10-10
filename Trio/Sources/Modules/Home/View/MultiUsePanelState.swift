import Foundation

/// Content states of the Home multi-use panel; highest priority wins.
enum MultiUsePanelState: Equatable {
    case notificationsDisabled
    case pumpTimeMismatch
    case cgmStale
    case maxIOBZero
    case preBolusCountdown(PendingPreBolusReminder)
    case whatsNew
    case dosingModeLimited(DosingMode)
    case stats

    /// readings older than this offer manual glucose entry
    static let cgmStaleAfter: TimeInterval = 12 * 60

    static func resolve(
        notificationsDisabled: Bool,
        pumpTimeMismatch: Bool,
        lastGlucoseDate: Date?,
        maxIOB: Decimal,
        pendingPreBolusReminder: PendingPreBolusReminder?,
        hasUnacknowledgedReleaseNotes: Bool,
        dosingMode: DosingMode,
        now: Date
    ) -> MultiUsePanelState {
        if notificationsDisabled { return .notificationsDisabled }
        if pumpTimeMismatch { return .pumpTimeMismatch }
        if now.timeIntervalSince(lastGlucoseDate ?? .distantPast) > cgmStaleAfter { return .cgmStale }
        // A pending pre-bolus is time-sensitive, so it outranks the deliberate, persistent states
        // below but still yields to the "something is broken right now" warnings above.
        if let pendingPreBolusReminder { return .preBolusCountdown(pendingPreBolusReminder) }
        // constrained modes clamp Max IOB to 0 without touching the stored value
        if dosingMode.automation == .reductionsOnly || dosingMode.automation == .hypoSuspendOnly {
            return .dosingModeLimited(dosingMode)
        }
        if maxIOB <= 0 { return .maxIOBZero }
        // Informational, so it yields to every warning above but still displaces the stats.
        if hasUnacknowledgedReleaseNotes { return .whatsNew }
        return .stats
    }
}
