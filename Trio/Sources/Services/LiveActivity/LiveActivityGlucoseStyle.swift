import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

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

    /// Point size of the reading at the default text size. Each step is clearly larger than the last, and
    /// Extra Large fills the widget. Scaled with the user's text size via `UIFontMetrics` (see `glucoseFont`).
    var basePointSize: CGFloat {
        switch self {
        case .small:
            return 30
        case .medium:
            return 40
        case .large:
            return 50
        case .extraLarge:
            return 64
        }
    }

    /// Vertical padding the Simple Live Activity row should use around the reading; nil = the layout's default.
    /// Extra Large drops it so the reading can use the whole height of the Live Activity.
    var verticalPadding: CGFloat? {
        self == .extraLarge ? 0 : nil
    }

    #if canImport(UIKit)
        /// Text style whose Dynamic Type scaling `basePointSize` follows.
        var uiTextStyle: UIFont.TextStyle {
            switch self {
            case .small:
                return .title2
            case .medium:
                return .title1
            case .large,
                 .extraLarge:
                return .largeTitle
            }
        }
    #else
        var textStyle: Font.TextStyle {
            switch self {
            case .small:
                return .title2
            case .medium:
                return .title
            case .large,
                 .extraLarge:
                return .largeTitle
            }
        }
    #endif

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
        #if canImport(UIKit)
            // SwiftUI's `.system(size:design:)` reliably renders the design (SF Rounded, New York, SF Mono); the
            // earlier UIFontDescriptor route silently dropped `.rounded`. `UIFontMetrics` keeps the size following the
            // user's text size setting.
            let scaled = UIFontMetrics(forTextStyle: fontSize.uiTextStyle).scaledValue(for: fontSize.basePointSize)
            return .system(size: scaled, weight: .bold, design: fontFace.design)
        #else
            return .system(fontSize.textStyle, design: fontFace.design).weight(.bold)
        #endif
    }
}
