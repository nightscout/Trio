import Foundation

enum ForecastDisplayType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case cone
    case lines
    var displayName: String {
        switch self {
        case .cone:
            return String(localized: "Cone", comment: "")

        case .lines:
            return String(localized: "Lines", comment: "")
        }
    }
}
