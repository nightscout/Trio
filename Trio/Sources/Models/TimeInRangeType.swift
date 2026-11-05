import Foundation

// Keep legacy case names for saved settings compatibility.
enum TimeInRangeType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case timeInTightRange
    case timeInNormoglycemia

    func displayName(for units: GlucoseUnits) -> String {
        let threshold = bottomThreshold.formatted(withUnits: units)
        switch self {
        case .timeInTightRange:
            return String(localized: "Standard (\(threshold))", comment: "Standard lower threshold for TIR and TITR statistics")

        case .timeInNormoglycemia:
            return String(localized: "Extended (\(threshold))", comment: "Extended lower threshold for TIR and TITR statistics")
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
