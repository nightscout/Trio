//
//  UserDefaults.swift
//  RileyLink
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit
import RileyLinkKit
import RileyLinkBLEKit

extension UserDefaults {
    private enum Key: String {
        case pumpManagerRawValue = "com.rileylink.PumpManagerRawValue"
        case rileyLinkConnectionManagerState = "com.rileylink.RileyLinkConnectionManagerState"
    }
    
    var pumpManagerRawValue: PumpManager.RawStateValue? {
        get {
            return dictionary(forKey: Key.pumpManagerRawValue.rawValue)
        }
        set {
            set(newValue, forKey: Key.pumpManagerRawValue.rawValue)
        }
    }
    
    var rileyLinkConnectionManagerState: RileyLinkConnectionState? {
        get {
            guard let rawValue = dictionary(forKey: Key.rileyLinkConnectionManagerState.rawValue) else
            {
                return nil
            }
            return RileyLinkConnectionState(rawValue: rawValue)
        }
        set {
            set(newValue?.rawValue, forKey: Key.rileyLinkConnectionManagerState.rawValue)
        }
    }

}

