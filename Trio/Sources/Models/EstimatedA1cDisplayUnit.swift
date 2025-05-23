// Trio
// EstimatedA1cDisplayUnit.swift
// Created by Deniz Cengiz on 2025-04-21.

import Foundation

enum EstimatedA1cDisplayUnit: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case percent
    case mmolMol

    var displayName: String {
        switch self {
        case .percent:
            return String(localized: "Percent", comment: "")
        case .mmolMol:
            return String(localized: "mmol/mol", comment: "")
        }
    }
}
