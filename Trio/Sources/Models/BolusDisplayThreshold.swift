import Foundation

enum BolusDisplayThreshold: Decimal, JSON, CaseIterable, Identifiable, Codable, Hashable {
    public var id: Decimal { rawValue }
    case oneUnit = 1
    case halfUnit = 0.5
    case pointOneUnit = 0.1
    case allUnits = 0.01

    var displayName: String {
        switch self {
        case .oneUnit:
            return String(localized: "1 U and over")
        case .halfUnit:
            return String(localized: "0.5 U and over")
        case .pointOneUnit:
            return String(localized: "0.1 U and over")
        case .allUnits:
            return String(localized: "Show All")
        }
    }
}
