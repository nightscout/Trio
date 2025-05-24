//
// Trio
// UserDefaultsExtensions.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation
import LoopKit
import RileyLinkBLEKit
import RileyLinkKit

extension UserDefaults {
    private enum Key: String {
        case legacyPumpManagerRawValue = "com.rileylink.PumpManagerRawValue"
        case rileyLinkConnectionManagerState = "com.rileylink.RileyLinkConnectionManagerState"
        case legacyPumpManagerState = "com.loopkit.Loop.PumpManagerState"
        case legacyCGMManagerState = "com.loopkit.Loop.CGMManagerState"
    }

    var rileyLinkConnectionManagerState: RileyLinkConnectionState? {
        get {
            guard let rawValue = dictionary(forKey: Key.rileyLinkConnectionManagerState.rawValue)
            else {
                return nil
            }
            return RileyLinkConnectionState(rawValue: rawValue)
        }
        set {
            set(newValue?.rawValue, forKey: Key.rileyLinkConnectionManagerState.rawValue)
        }
    }

    var legacyPumpManagerRawValue: PumpManager.RawValue? {
        dictionary(forKey: Key.legacyPumpManagerRawValue.rawValue)
    }

    func clearLegacyPumpManagerRawValue() {
        set(nil, forKey: Key.legacyPumpManagerRawValue.rawValue)
    }

    var legacyCGMManagerRawValue: CGMManager.RawValue? {
        dictionary(forKey: Key.legacyCGMManagerState.rawValue)
    }

    func clearLegacyCGMManagerRawValue() {
        set(nil, forKey: Key.legacyCGMManagerState.rawValue)
    }
}
