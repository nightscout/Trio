//
//  LibreDemoPlugin.swift
//  LibreTransmitter
//
//  Created by Pete Schwamb on 6/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import LibreTransmitter
import LibreTransmitterUI

import os.log

class LibreDemoPlugin: NSObject, CGMManagerUIPlugin {

    private let log = OSLog(category: "LibreDemoPlugin")

    public var pumpManagerType: PumpManagerUI.Type? {
        nil
    }

    public var cgmManagerType: CGMManagerUI.Type? {
        LibreDemoCGMManager.self
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
