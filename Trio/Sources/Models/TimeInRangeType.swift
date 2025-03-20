import Foundation

enum TimeInRangeType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case timeInTightRange
    case timeInNormoglycemia
    var displayName: String {
        switch self {
        case .timeInTightRange:
            return String(localized: "Time in Tight Range (TITR)", comment: "")

        case .timeInNormoglycemia:
            return String(localized: "Time in Normoglycemia (TING)", comment: "")
        }
    }
}
