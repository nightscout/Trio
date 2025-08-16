import CGMBLEKit
import Foundation
import G7SensorKit
import G7SensorKitUI
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import Swinject

protocol PluginManager {
    var availableCGMManagers: [CGMManagerDescriptor] { get }
    func getCGMManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type?
}

class BasePluginManager: Injectable, PluginManager {
    struct CgmPluginDescription {
        let pluginIdentifier: String
        let localizedTitle: String
        let manager: CGMManagerUI.Type
    }

    static let cgms = [
        CgmPluginDescription(
            pluginIdentifier: G5CGMManager.pluginIdentifier,
            localizedTitle: String(localized: "Dexcom G5"),
            manager: G5CGMManager.self
        ),
        CgmPluginDescription(
            pluginIdentifier: G6CGMManager.pluginIdentifier,
            localizedTitle: String(localized: "Dexcom G6 / ONE"),
            manager: G6CGMManager.self
        ),
        CgmPluginDescription(
            pluginIdentifier: G7CGMManager.pluginIdentifier,
            localizedTitle: String(localized: "Dexcom G7 / ONE+"),
            manager: G7CGMManager.self
        ),
        CgmPluginDescription(
            pluginIdentifier: LibreTransmitterManagerV3.pluginIdentifier,
            localizedTitle: String(localized: "FreeStyle Libre"),
            manager: LibreTransmitterManagerV3.self
        )
    ]

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func getCGMManagerTypeByIdentifier(_ pluginIdentifier: String) -> CGMManagerUI.Type? {
        BasePluginManager.cgms.filter({ $0.pluginIdentifier == pluginIdentifier }).first?.manager
    }

    var availableCGMManagers: [CGMManagerDescriptor] {
        BasePluginManager.cgms.map { CGMManagerDescriptor(identifier: $0.pluginIdentifier, localizedTitle: $0.localizedTitle) }
    }
}
