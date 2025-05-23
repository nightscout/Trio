// Trio
// ColorSchemeOption.swift
// Created by Deniz Cengiz on 2024-09-20.

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
