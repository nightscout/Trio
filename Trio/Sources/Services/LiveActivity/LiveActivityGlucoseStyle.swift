import Foundation
import SwiftUI
import UIKit

/// Size of the glucose reading shown by the Simple Lock Screen Live Activity.
///
/// Compiled into both the Trio app (settings UI and its live preview) and the Live Activity extension (rendering).
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
        let scaled = UIFontMetrics(forTextStyle: fontSize.uiTextStyle).scaledValue(for: fontSize.basePointSize)
        return .system(size: scaled, weight: .bold)
    }
}
