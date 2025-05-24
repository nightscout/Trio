//
// Trio
// ForecastDisplayType.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-02-19.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation

enum ForecastDisplayType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case cone
    case lines
    var displayName: String {
        switch self {
        case .cone:
            return String(localized: "Cone", comment: "")

        case .lines:
            return String(localized: "Lines", comment: "")
        }
    }
}
