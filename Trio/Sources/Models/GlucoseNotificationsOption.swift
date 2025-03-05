//
//  GlucoseNotificationOption.swift
//  FreeAPS
//
//  Created by Kimberlie Skandis on 1/18/25.
//
import Foundation
import SwiftUI

public enum GlucoseNotificationsOption: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    case disabled
    case alwaysEveryCGM
    case onlyAlarmLimits

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled:
            return String(localized: "Disabled", comment: "Option to disable glucose notifications")
        case .alwaysEveryCGM:
            return String(localized: "Always", comment: "Option to always notify on every CGM reading")
        case .onlyAlarmLimits:
            return String(localized: "Only Alarm Limits", comment: "Option to notify only when glucose reaches alarm limits")
        }
    }
}
