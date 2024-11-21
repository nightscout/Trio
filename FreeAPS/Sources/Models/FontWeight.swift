import Foundation

enum FontWeight: String, JSON, Identifiable, CaseIterable, Codable {
    var id: String { rawValue }

    case light
    case regular
    case medium
    case semibold
    case bold
    case black

    var displayName: String {
        switch self {
        case .light:
            return NSLocalizedString("LightFontWeight", comment: "")
        case .regular:
            return NSLocalizedString("RegularFontWeight", comment: "")
        case .medium:
            return NSLocalizedString("MediumFontWeight", comment: "")
        case .semibold:
            return NSLocalizedString("SemiboldFontWeight", comment: "")
        case .bold:
            return NSLocalizedString("BoldFontWeight", comment: "")
        case .black:
            return NSLocalizedString("BlackFontWeight", comment: "")
        }
    }
}
