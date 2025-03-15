import Foundation

enum EstimatedA1cDisplayUnit: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case percent
    case mmolMol

    var displayName: String {
        switch self {
        case .percent:
            return String(localized: "Percent", comment: "")
        case .mmolMol:
            return String(localized: "mmol/mol", comment: "")
        }
    }
}
