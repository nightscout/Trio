//
//  PumpManagerState.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import MinimedKit
import RileyLinkBLEKit
import OmniKit


let allPumpManagers: [String: PumpManager.Type] = [
    MinimedPumpManager.managerIdentifier: MinimedPumpManager.self
]

func PumpManagerFromRawValue(_ rawValue: [String: Any], rileyLinkDeviceProvider: RileyLinkDeviceProvider) -> PumpManager? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String,
        let rawState = rawValue["state"] as? PumpManager.RawStateValue
        else {
            return nil
    }
    
    switch (managerIdentifier) {
    case MinimedPumpManager.managerIdentifier:
        guard let state = MinimedPumpManagerState(rawValue: rawState) else {
            return nil
        }
        return MinimedPumpManager(state: state, rileyLinkDeviceProvider: rileyLinkDeviceProvider)
    case OmnipodPumpManager.managerIdentifier:
        guard let state = OmnipodPumpManagerState(rawValue: rawState) else {
            return nil
        }
        return OmnipodPumpManager(state: state, rileyLinkDeviceProvider: rileyLinkDeviceProvider)
    default:
        return nil
    }
}

extension PumpManager {
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": self.rawState
        ]
    }
}
