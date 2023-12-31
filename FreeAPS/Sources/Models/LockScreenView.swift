import Foundation

enum LockScreenView: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case simple
    case detailed
    var displayName: String {
        switch self {
        case .simple:
            return NSLocalizedString("Simple", comment: "")
        case .detailed:
            return NSLocalizedString("Detailed", comment: "")
        }
    }
}
