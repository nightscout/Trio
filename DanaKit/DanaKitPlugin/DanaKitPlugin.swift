import DanaKit
import Foundation
import LoopKitUI
import os.log

class DanaKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "DanaKitPlugin")

    public var pumpManagerType: PumpManagerUI.Type? {
        DanaKitPumpManager.self
    }

    public var cgmManagerType: CGMManagerUI.Type? {
        nil
    }

    override init() {
        super.init()
        log.default("DanaKitPlugin Instantiated")
    }
}
