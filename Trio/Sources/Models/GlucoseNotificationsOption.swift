//
//  GlucoseNotificationOption.swift
//  FreeAPS
//
//  Created by Kimberlie Skandis on 1/18/25.
//
import Foundation
import SwiftUI

public enum GlucoseNotificationsOption: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    case disabled = "Disabled"
    case alwaysEveryCGM = "Always"
    case onlyAlarmLimits = "Only Alarm Limits"

    public var id: String { rawValue }

    var localized: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}
