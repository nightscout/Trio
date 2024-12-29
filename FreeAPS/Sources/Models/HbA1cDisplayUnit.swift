import Foundation

enum HbA1cDisplayUnit: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case percent
    case mmolMol

    var displayName: String {
        switch self {
        case .percent:
            return NSLocalizedString("Percent", comment: "")
        case .mmolMol:
            return NSLocalizedString("mmol/mol", comment: "")
        }
    }
}
