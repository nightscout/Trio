import Foundation
import LoopKit
import LoopKitUI
import Swinject

protocol PluginManager {
    var availableCGMManagers: [CGMManagerDescriptor] { get }
    func getCGMManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type?
}

/// Exposes the manager-backed CGMs from `DeviceCatalog` in LoopKit's descriptor vocabulary.
///
/// Named "plugin" for historical reasons only: Trio statically links every kit rather than loading bundles.
class BasePluginManager: Injectable, PluginManager {
    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func getCGMManagerTypeByIdentifier(_ pluginIdentifier: String) -> CGMManagerUI.Type? {
        DeviceCatalog.cgmEntry(id: pluginIdentifier)?.managerType
    }

    var availableCGMManagers: [CGMManagerDescriptor] {
        DeviceCatalog.cgmManagerEntries.map {
            CGMManagerDescriptor(identifier: $0.id, localizedTitle: $0.name)
        }
    }
}
