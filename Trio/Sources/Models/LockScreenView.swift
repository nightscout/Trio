// Trio
// LockScreenView.swift
// Created by polscm32 on 2023-12-31.

import Foundation

enum LockScreenView: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case simple
    case detailed
    var displayName: String {
        switch self {
        case .simple:
            return String(localized: "Simple", comment: "")
        case .detailed:
            return String(localized: "Detailed", comment: "")
        }
    }
}
