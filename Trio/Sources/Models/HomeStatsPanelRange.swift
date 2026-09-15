import Foundation

/// Time span the home screen statistics panel (and the Statistics screen it opens)
/// reports over. Mirrors `Stat.StateModel.StatsTimeIntervalWithToday`, which is a
/// view-layer enum and therefore not persistable in `TrioSettings`.
enum HomeStatsPanelRange: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    /// Midnight until now.
    case today
    /// Trailing 24 hours.
    case day
    /// Trailing 7 days.
    case week
    /// Trailing 30 days.
    case month
    /// Trailing 90 days.
    case threeMonths

    var displayName: String {
        switch self {
        case .today:
            return String(localized: "Today", comment: "Home stats panel range option")
        case .day:
            return String(localized: "Last day", comment: "Home stats panel range option")
        case .week:
            return String(localized: "Last week", comment: "Home stats panel range option")
        case .month:
            return String(localized: "Last month", comment: "Home stats panel range option")
        case .threeMonths:
            return String(localized: "Last 3 months", comment: "Home stats panel range option")
        }
    }

    /// Possessive form used where the panel reads "Today's …".
    var possessiveName: String {
        switch self {
        case .today:
            return String(localized: "Today's", comment: "Home stats panel range, possessive")
        case .day:
            return String(localized: "Last day's", comment: "Home stats panel range, possessive")
        case .week:
            return String(localized: "Last week's", comment: "Home stats panel range, possessive")
        case .month:
            return String(localized: "Last month's", comment: "Home stats panel range, possessive")
        case .threeMonths:
            return String(localized: "Last 3 months'", comment: "Home stats panel range, possessive")
        }
    }

    /// Trailing scope wording, as in "Time in Range today".
    var scopeName: String {
        switch self {
        case .today:
            return String(localized: "today", comment: "Home stats panel range, trailing scope")
        case .day:
            return String(localized: "last day", comment: "Home stats panel range, trailing scope")
        case .week:
            return String(localized: "last week", comment: "Home stats panel range, trailing scope")
        case .month:
            return String(localized: "last month", comment: "Home stats panel range, trailing scope")
        case .threeMonths:
            return String(localized: "last 3 months", comment: "Home stats panel range, trailing scope")
        }
    }

    /// Leading edge of the range, relative to `date`.
    func startDate(relativeTo date: Date = Date()) -> Date {
        switch self {
        case .today:
            return Calendar.current.startOfDay(for: date)
        case .day:
            return date.addingTimeInterval(-24 * 3600)
        case .week:
            return date.addingTimeInterval(-7 * 24 * 3600)
        case .month:
            return date.addingTimeInterval(-30 * 24 * 3600)
        case .threeMonths:
            return date.addingTimeInterval(-90 * 24 * 3600)
        }
    }
}
