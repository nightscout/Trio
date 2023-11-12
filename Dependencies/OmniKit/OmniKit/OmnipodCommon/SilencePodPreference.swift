//
//  SilencePodPreference.swift
//  OmniKit
//
//  Created by Joe Moran on 8/30/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

public enum SilencePodPreference: Int, CaseIterable {
    case disabled
    case enabled

    public var title: String {
        switch self {
        case .disabled:
            return LocalizedString("Disabled", comment: "Title string for SilencePodPreference.disabled")
        case .enabled:
            return LocalizedString("Silenced", comment: "Title string for SilencePodPreference.enabled")
        }
    }

    public var description: String {
        switch self {
        case .disabled:
            return LocalizedString("Normal operation mode where audible Pod beeps are used for all Pod alerts and when confidence reminders are enabled.", comment: "Description for SilencePodPreference.disabled")
        case .enabled:
            return LocalizedString("All Pod alerts use no beeps and confirmation reminder beeps are suppressed. The Pod will only beep for fatal Pod faults and when playing test beeps.\n\n⚠️Warning - Whenever the Pod is silenced it must be kept within Bluetooth range of this device to receive notifications for Pod alerts.", comment: "Description for SilencePodPreference.enabled")
        }
    }
}
