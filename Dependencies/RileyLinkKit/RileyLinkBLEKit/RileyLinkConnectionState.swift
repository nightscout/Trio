//
//  RileyLinkConnectionManagerState.swift
//  RileyLinkBLEKit
//
//  Created by Pete Schwamb on 8/21/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct RileyLinkConnectionState: RawRepresentable, Equatable {
    
    public typealias RawValue = RileyLinkDeviceProvider.RawStateValue
    
    public var autoConnectIDs: Set<String>

    public init(autoConnectIDs: Set<String>) {
        self.autoConnectIDs = autoConnectIDs
    }
    
    public init?(rawValue: RileyLinkDeviceProvider.RawStateValue) {
        guard
            let autoConnectIDs = rawValue["autoConnectIDs"] as? [String]
            else {
                return nil
        }
        
        self.init(autoConnectIDs: Set(autoConnectIDs))
    }
    
    public var rawValue: RawValue {
        return [
            "autoConnectIDs": Array(autoConnectIDs),
        ]
    }

    
    
}
