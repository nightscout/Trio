//
// Trio
// GlucoseColorScheme.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by dsnallfot on 2025-03-03.
// Most contributions by Marvin Polscheit and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI
import UIKit

public enum GlucoseColorScheme: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    public var id: String { rawValue }
    case staticColor
    case dynamicColor

    var displayName: String {
        switch self {
        case .staticColor:
            return String(localized: "Static")
        case .dynamicColor:
            return String(localized: "Dynamic")
        }
    }
}

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
