import SwiftUI

extension Font.Weight {
    var displayName: String {
        switch self {
        case .ultraLight: return "Ultra Light"
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        case .black: return "Black"
        default: return "Unknown"
        }
    }

    private static let stringToFontWeight: [String: Font.Weight] = [
        "ultraLight": .ultraLight,
        "thin": .thin,
        "light": .light,
        "regular": .regular,
        "medium": .medium,
        "semibold": .semibold,
        "bold": .bold,
        "heavy": .heavy,
        "black": .black
    ]

    private static let fontWeightToString: [Font.Weight: String] = [
        .ultraLight: "ultraLight",
        .thin: "thin",
        .light: "light",
        .regular: "regular",
        .medium: "medium",
        .semibold: "semibold",
        .bold: "bold",
        .heavy: "heavy",
        .black: "black"
    ]

    /// Initialize `Font.Weight` from a string
    static func fromString(_ string: String) -> Font.Weight {
        stringToFontWeight[string] ?? .regular // Default fallback
    }

    /// Convert `Font.Weight` to a string
    var asString: String {
        Font.Weight.fontWeightToString[self] ?? "regular" // Default fallback
    }
}

extension Font.Width {
    var displayName: String {
        switch self {
        case .condensed: return "Condensed"
        case .expanded: return "Expanded"
        case .compressed: return "Compressed"
        case .standard: return "Standard"
        default: return "Unknown"
        }
    }

    private static let stringToFontWidth: [String: Font.Width] = [
        "compressed": .compressed,
        "condensed": .condensed,
        "standard": .standard,
        "expanded": .expanded
    ]

    private static let fontWidthToString: [Font.Width: String] = [
        .compressed: "compressed",
        .condensed: "condensed",
        .standard: "standard",
        .expanded: "expanded"
    ]

    /// Initialize `Font.Width` from a string
    static func fromString(_ string: String) -> Font.Width {
        stringToFontWidth[string] ?? .standard // Default fallback
    }

    /// Convert `Font.Width` to a string
    var asString: String {
        Font.Width.fontWidthToString[self] ?? "standard" // Default fallback
    }
}
