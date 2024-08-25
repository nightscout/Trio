//
//  TotalInsulinDisplayType.swift
//  FreeAPS
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
            return NSLocalizedString("Total Daily Dose", comment: "")
        case .totalInsulinInScope:
            return NSLocalizedString("Total Insulin in Scope", comment: "")
        }
    }
}
