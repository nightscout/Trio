//
// Trio
// LockScreenView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-02-19.
// Most contributions by Marvin Polscheit and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

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
