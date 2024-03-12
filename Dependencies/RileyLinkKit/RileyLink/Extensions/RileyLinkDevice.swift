//
//  RileyLinkDevice.swift
//  RileyLink
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import RileyLinkBLEKit


extension RileyLinkDevice.IdleListeningState {
    static var enabledWithDefaults: RileyLinkDevice.IdleListeningState {
        return .enabled(timeout: .minutes(1), channel: 0)
    }
}
