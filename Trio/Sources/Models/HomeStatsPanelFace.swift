import Foundation

enum HomeStatsPanelFace: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case timeInRange
    case distributionBar
    case averages

    var displayName: String {
        switch self {
        case .timeInRange:
            return String(localized: "Time in Range", comment: "Home stats panel face option")
        case .distributionBar:
            return String(localized: "Distribution Bar Only", comment: "Home stats panel face option")
        case .averages:
            return String(localized: "Today's Averages", comment: "Home stats panel face option")
        }
    }
}
