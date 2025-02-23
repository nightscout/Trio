//
//  TotalInsulinDisplayType.swift
//  Trio
//
//  Created by Cengiz Deniz on 25.08.24.
//
import Foundation

enum TotalInsulinDisplayType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case totalDailyDose
    case totalInsulinInScope

    var displayName: String {
        switch self {
        case .totalDailyDose:
            return String(localized: "TDD", comment: "")
        case .totalInsulinInScope:
            return String(localized: "TINS", comment: "")
        }
    }
}
