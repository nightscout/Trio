import Foundation

enum LockScreenView: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case simple
    case detailed
    var displayName: String {
        switch self {
        case .simple:
            return String(localized: "Simple", comment: "")
        case .detailed:
            return String(localized: "Detailed", comment: "")
        }
    }
}
