//
//  GlucoseColorScheme.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 27.09.24.
//
import Foundation

public enum GlucoseColorScheme: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    public var id: String { rawValue }
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
