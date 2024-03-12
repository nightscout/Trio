//
//  LibreTransmitterPlugin.swift
//  LibreTransmitterPlugin
//
//  Created by Nathaniel Hamming on 2019-12-19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI
import LibreTransmitter
import LibreTransmitterUI

import os.log

class LibreTransmitterPlugin: NSObject, CGMManagerUIPlugin {
    
    private let log = OSLog(category: "LibreTransmitterPlugin")
    
    public var pumpManagerType: PumpManagerUI.Type? {
        nil
    }
    
    public var cgmManagerType: CGMManagerUI.Type? {
        LibreTransmitterManagerV3.self
    }
    
    override init() {
        super.init()
        log.default("Instantiated")
        LibreTransmitter.AppMetaData.allProperties = allProperties

    }

    let prefix = "com-loopkit-libre"
    let bundle = Bundle(for: LibreTransmitterPlugin.self)

    var allProperties: String {
        bundle.infoDictionary?.compactMap {
            $0.key.starts(with: prefix) ? "\($0.key): \($0.value)" : nil
        }.joined(separator: "\n") ?? "none"
    }
}
