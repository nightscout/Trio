//
// Trio
// EstimatedA1cDisplayUnit.swift
// Created by Deniz Cengiz on 2025-02-23.
// Last edited by Deniz Cengiz on 2025-02-23.
// Most contributions by tmhastings and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

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
