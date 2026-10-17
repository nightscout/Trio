import Foundation
import SwiftUI
import UIKit

enum LiveActivityFontSize: String, Codable, Hashable, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

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

    var verticalPadding: CGFloat? {
        self == .extraLarge ? 0 : nil
    }

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
    var glucoseFont: Font {
        let scaled = UIFontMetrics(forTextStyle: fontSize.uiTextStyle).scaledValue(for: fontSize.basePointSize)
        return .system(size: scaled, weight: .bold)
    }
}
