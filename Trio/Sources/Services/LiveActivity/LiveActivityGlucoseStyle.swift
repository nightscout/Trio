import Foundation
import SwiftUI

/// Typeface of the glucose reading shown by the Simple Lock Screen Live Activity.
///
/// This file is compiled into both the Trio app (settings UI and its live preview) and the Live Activity
/// extension (rendering), so it must not reference anything only one of the two targets can see.
enum LiveActivityFontFace: String, Codable, Hashable, CaseIterable, Identifiable {
    case `default`
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .default:
            return .default
        case .rounded:
            return .rounded
        case .serif:
            return .serif
        case .monospaced:
            return .monospaced
        }
    }

    var displayName: String {
        switch self {
        case .default:
            return String(localized: "Default", comment: "Live Activity glucose reading font face")
        case .rounded:
            return String(localized: "Rounded", comment: "Live Activity glucose reading font face")
        case .serif:
            return String(localized: "Serif", comment: "Live Activity glucose reading font face")
        case .monospaced:
            return String(localized: "Monospaced", comment: "Live Activity glucose reading font face")
        }
    }
}

/// Size of the glucose reading shown by the Simple Lock Screen Live Activity.
///
/// Backed by Dynamic Type text styles, so the reading keeps scaling with the user's preferred text size.
enum LiveActivityFontSize: String, Codable, Hashable, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var textStyle: Font.TextStyle {
        switch self {
        case .small:
            return .title3
        case .medium:
            return .title2
        case .large:
            return .title
        case .extraLarge:
            return .largeTitle
        }
    }

    var displayName: String {
        switch self {
        case .small:
            return String(localized: "Small", comment: "Live Activity glucose reading font size")
        case .medium:
            return String(localized: "Medium", comment: "Live Activity glucose reading font size")
        case .large:
            return String(localized: "Large", comment: "Live Activity glucose reading font size")
        case .extraLarge:
            return String(localized: "Extra Large", comment: "Live Activity glucose reading font size")
        }
    }
}

extension LiveActivityAttributes.SimpleViewStyle {
    /// Font applied to the glucose reading and its trend arrow in the Simple Lock Screen Live Activity.
    var glucoseFont: Font {
        .system(fontSize.textStyle, design: fontFace.design)
    }

    /// Resolves the color of the glucose reading.
    ///
    /// - Parameter glucoseColor: The color derived from Trio's glucose color scheme for the current reading.
    /// - Returns: `glucoseColor` if the user opted into colored readings, otherwise the default text color.
    func readingColor(_ glucoseColor: Color) -> Color {
        useGlucoseColor ? glucoseColor : .primary
    }
}
