//
// Trio
// ColorSchemeOption.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by dsnallfot on 2025-03-03.
// Most contributions by Deniz Cengiz and dsnallfot.
//
// Documentation available under: https://triodocs.org/

enum ColorSchemeOption: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }

    case systemDefault
    case light
    case dark

    var displayName: String {
        switch self {
        case .systemDefault: return String(localized: "System Default")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}
