import Foundation

enum HomeStatsPanelFace: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case timeInRange
    case distributionBar
    case averages
    case loopingPerformance
    case totalDailyDose
    case none

    var displayName: String {
        switch self {
        case .timeInRange:
            return String(localized: "Time in Range", comment: "Home stats panel face option")
        case .distributionBar:
            return String(localized: "Distribution Bar Only", comment: "Home stats panel face option")
        case .averages:
            return String(localized: "Averages", comment: "Home stats panel face option")
        case .loopingPerformance:
            return String(localized: "Looping Performance", comment: "Home stats panel face option")
        case .totalDailyDose:
            return String(localized: "Total Daily Dose", comment: "Home stats panel face option")
        case .none:
            return String(localized: "None", comment: "Home stats panel face option")
        }
    }
}
