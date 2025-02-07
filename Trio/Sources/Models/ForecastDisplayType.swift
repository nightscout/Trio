import Foundation

enum ForecastDisplayType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case cone
    case lines
    var displayName: String {
        switch self {
        case .cone:
            return NSLocalizedString("Cone", comment: "")

        case .lines:
            return NSLocalizedString("Lines", comment: "")
        }
    }
}
