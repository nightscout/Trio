import Foundation

enum HomeStatsPanelFace: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case timeInRange
    case distributionBar
    case averages
    case hidden

    var displayName: String {
        switch self {
        case .timeInRange:
            return String(localized: "Time in Range", comment: "Home stats panel face option")
        case .distributionBar:
            return String(localized: "Distribution Bar Only", comment: "Home stats panel face option")
        case .averages:
            return String(localized: "Averages", comment: "Home stats panel face option")
        case .hidden:
            return String(localized: "Hide Statistics", comment: "Home stats panel face option")
        }
    }
}

/// Span the home stats panel reports on; the Statistics screen opens on the same span.
enum HomeStatsPanelRange: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case today
    case day
    case week
    case month
    case threeMonths

    var displayName: String {
        switch self {
        case .today:
            return String(localized: "Today")
        case .day:
            return String(localized: "Last 24 Hours", comment: "Home stats panel range option")
        case .week:
            return String(localized: "Last 7 Days", comment: "Home stats panel range option")
        case .month:
            return String(localized: "Last Month", comment: "Home stats panel range option")
        case .threeMonths:
            return String(localized: "Last 3 Months", comment: "Home stats panel range option")
        }
    }

    /// Trailing scope, as in "Time in Range today".
    var scopeName: String {
        switch self {
        case .today:
            return String(localized: "today", comment: "Stats banner scope")
        case .day:
            return String(localized: "last 24 hours", comment: "Stats banner scope")
        case .week:
            return String(localized: "last 7 days", comment: "Stats banner scope")
        case .month:
            return String(localized: "last month", comment: "Stats banner scope")
        case .threeMonths:
            return String(localized: "last 3 months", comment: "Stats banner scope")
        }
    }

    /// Subtitle of the averages face.
    var averageSubtitle: String {
        switch self {
        case .today:
            return String(localized: "Today's Average", comment: "Stats banner subtitle")
        case .day:
            return String(localized: "Average of the Last 24 Hours", comment: "Stats banner subtitle")
        case .week:
            return String(localized: "Average of the Last 7 Days", comment: "Stats banner subtitle")
        case .month:
            return String(localized: "Average of the Last Month", comment: "Stats banner subtitle")
        case .threeMonths:
            return String(localized: "Average of the Last 3 Months", comment: "Stats banner subtitle")
        }
    }

    /// Leading edge of the span. Same calendar arithmetic as the Statistics screen's
    /// glucose fetches (`Date.oneDayAgo` … `Date.threeMonthsAgo`), so the numbers match.
    func startDate(relativeTo now: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .day:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        }
    }

    /// Whether the chart's in-memory glucose (72 h) already covers the span.
    var isCoveredByChartHistory: Bool {
        self == .today || self == .day
    }
}
