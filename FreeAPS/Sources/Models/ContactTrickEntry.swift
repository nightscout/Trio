import SwiftUI

struct ContactTrickEntry: Hashable, Sendable {
    var layout: ContactTrickLayout = .single
    var ring1: ContactTrickLargeRing = .none
    var primary: ContactTrickValue = .glucose
    var top: ContactTrickValue = .none
    var bottom: ContactTrickValue = .none
    var contactId: String? = nil
    var darkMode: Bool = true
    var ringWidth: RingWidth = .regular
    var ringGap: RingGap = .small
    var fontSize: FontSize = .regular
    var secondaryFontSize: FontSize = .small
    var fontWeight: Font.Weight = .medium
    var fontWidth: Font.Width = .standard

    // Convert `fontWeight` to a String for Core Data storage
    var fontWeightString: String {
        fontWeight.asString
    }

    // Initialize `fontWeight` from a String
    static func fontWeight(from string: String) -> Font.Weight {
        Font.Weight.fromString(string)
    }

    // Convert `fontWidth` to a String for Core Data storage
    var fontWidthString: String {
        fontWidth.asString
    }

    // Initialize `fontWidth` from a String
    static func fontWidth(from string: String) -> Font.Width {
        Font.Width.fromString(string)
    }

    enum FontSize: Int, Sendable {
        case tiny = 200
        case small = 250
        case regular = 300
        case large = 400

        var displayName: String {
            switch self {
            case .tiny: return "Tiny"
            case .small: return "Small"
            case .regular: return "Regular"
            case .large: return "Large"
            }
        }
    }

    enum RingWidth: Int, Sendable {
        case tiny = 3
        case small = 5
        case regular = 7
        case medium = 10
        case large = 15

        var displayName: String {
            switch self {
            case .tiny: return "Tiny"
            case .small: return "Small"
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    enum RingGap: Int, Sendable {
        case tiny = 1
        case small = 2
        case regular = 3
        case medium = 4
        case large = 5

        var displayName: String {
            switch self {
            case .tiny: return "Tiny"
            case .small: return "Small"
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }
}

// TODO: is this required?
protocol ContactTrickObserver: Sendable {
    func basalProfileDidChange(_ entry: [ContactTrickEntry])
}

extension Font.Weight {
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .bold: return "Bold"
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
