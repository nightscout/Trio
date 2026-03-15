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

    var bottomThreshold: Int {
        switch self {
        case .timeInTightRange:
            return 70
        case .timeInNormoglycemia:
            return 63
        }
    }

    var topThreshold: Int {
        switch self {
        case .timeInNormoglycemia,
             .timeInTightRange:
            return 140
        }
    }
}
