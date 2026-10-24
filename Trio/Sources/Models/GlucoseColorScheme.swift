import Foundation
import SwiftUI
import UIKit

public enum GlucoseColorScheme: String, CaseIterable, Identifiable, Codable, Hashable {
    public var id: String { rawValue }
    case dynamicColor
    case staticColor

    var displayName: String {
        switch self {
        case .dynamicColor:
            return String(localized: "Dynamic")
        case .staticColor:
            return String(localized: "Static")
        }
    }
}

// The watch app colors its readings with this file and DynamicGlucoseColor.swift, without Trio's JSON helpers.
#if os(iOS)
    extension GlucoseColorScheme: JSON {}
#endif

extension Color {
    func toHexString() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
