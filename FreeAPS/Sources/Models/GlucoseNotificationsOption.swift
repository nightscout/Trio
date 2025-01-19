//
//  GlucoseNotificationOption.swift
//  FreeAPS
//
//  Created by Kimberlie Skandis on 1/18/25.
//
import Foundation

public enum GlucoseNotificationsOption: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    public var id: String { rawValue }
    case disabled
    case alwaysEveryCGM
    case onlyLowHigh

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .alwaysEveryCGM: return "Always"
        case .onlyLowHigh: return "Low/High Alarms"
        }
    }
}
