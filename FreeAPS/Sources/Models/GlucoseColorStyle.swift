//
//  GlucoseColorStyle.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 27.09.24.
//
import Foundation

enum GlucoseColorStyle: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case staticColor
    case dynamicColor

    var displayName: String {
        switch self {
        case .staticColor:
            return "Static"
        case .dynamicColor:
            return "Dynamic"
        }
    }
}
