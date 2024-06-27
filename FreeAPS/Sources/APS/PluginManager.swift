import Foundation
import LoopKit
import LoopKitUI
import Swinject

protocol PluginManager {
    var availablePumpManagers: [PumpManagerDescriptor] { get }
    var availableCGMManagers: [CGMManagerDescriptor] { get }
    var availableServices: [ServiceDescriptor] { get }
    func getPumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type?
    func getCGMManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type?
    func getServiceTypeByIdentifier(_ identifier: String) -> ServiceUI.Type?
}

class BasePluginManager: Injectable, PluginManager {
    let pluginBundles: [Bundle]

    init(resolver: Resolver) {
        let pluginsURL: URL? = Bundle.main.privateFrameworksURL
        var bundles = [Bundle]()

        if let pluginsURL = pluginsURL {
            do {
                for pluginURL in try FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil)
                    .filter({ $0.path.hasSuffix(".framework") })
                {
                    if let bundle = Bundle(url: pluginURL) {
                        if let bname = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                            debug(.deviceManager, "bundle name2:\(bname)")
                        }
                        if let bcgm = bundle.object(forInfoDictionaryKey: "com.loopkit.Loop.CGMManagerIdentifier") as? String {
                            debug(.deviceManager, "bundle is CGM")
                        }

                        if bundle.isLoopPlugin {
                            debug(.deviceManager, "Found loop plugin:\(pluginURL.absoluteString)")
                            bundles.append(bundle)
                        }
                    }
                }
            } catch {
                debug(.deviceManager, "Error loading plugin: \(error)")
            }
        }
        pluginBundles = bundles
        injectServices(resolver)
    }

    func getPumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String,
               name == identifier
            {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {
                        if let plugin = principalClass.init() as? PumpManagerUIPlugin {
                            return plugin.pumpManagerType
                        } else {
                            fatalError("PrincipalClass does not conform to PumpManagerUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch {
                    debug(.deviceManager, "Error loading plugin: \(error)")
                }
            }
        }
        return nil
    }

    var availablePumpManagers: [PumpManagerDescriptor] {
        pluginBundles.compactMap({ (bundle) -> PumpManagerDescriptor? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerDisplayName.rawValue) as? String,
                  let identifier = bundle
                  .object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String
            else {
                return nil
            }

            return PumpManagerDescriptor(identifier: identifier, localizedTitle: title)
        })
    }

    func getCGMManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String,
               name == identifier
            {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {
                        if let plugin = principalClass.init() as? CGMManagerUIPlugin {
                            return plugin.cgmManagerType
                        } else {
                            fatalError("PrincipalClass does not conform to CGMManagerUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch {
                    debug(.deviceManager, "Error loading plugin: \(error)")
                }
            }
        }
        return nil
    }

    var availableCGMManagers: [CGMManagerDescriptor] {
        pluginBundles.compactMap({ (bundle) -> CGMManagerDescriptor? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerDisplayName.rawValue) as? String,
                  let identifier = bundle
                  .object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String
            else {
                return nil
            }

            return CGMManagerDescriptor(identifier: identifier, localizedTitle: title)
        })
    }

    func getServiceTypeByIdentifier(_ identifier: String) -> ServiceUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String,
               name == identifier
            {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {
                        if let plugin = principalClass.init() as? ServiceUIPlugin {
                            return plugin.serviceType
                        } else {
                            fatalError("PrincipalClass does not conform to ServiceUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch {
                    debug(.deviceManager, "Error loading plugin: \(error)")
                }
            }
        }
        return nil
    }

    var availableServices: [ServiceDescriptor] {
        pluginBundles.compactMap({ (bundle) -> ServiceDescriptor? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceDisplayName.rawValue) as? String,
                  let identifier = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String
            else {
                return nil
            }

            return ServiceDescriptor(identifier: identifier, localizedTitle: title)
        })
    }

    func getStatefulPluginTypeByIdentifier(_ identifier: String) -> StatefulPluggable.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.statefulPluginIdentifier.rawValue) as? String,
               name == identifier
            {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {
                        if let plugin = principalClass.init() as? StatefulPlugin {
                            return plugin.pluginType
                        } else {
                            fatalError("PrincipalClass does not conform to StatefulPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch {
                    debug(.deviceManager, "Error loading plugin: \(error)")
                }
            }
        }
        return nil
    }

    var availableStatefulPluginIdentifiers: [String] {
        pluginBundles.compactMap({ (bundle) -> String? in
            bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.statefulPluginIdentifier.rawValue) as? String
        })
    }

    func getOnboardingTypeByIdentifier(_ identifier: String) -> OnboardingUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.onboardingIdentifier.rawValue) as? String,
               name == identifier
            {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {
                        if let plugin = principalClass.init() as? OnboardingUIPlugin {
                            return plugin.onboardingType
                        } else {
                            fatalError("PrincipalClass does not conform to OnboardingUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch {
                    debug(.deviceManager, "Error loading plugin: \(error)")
                }
            }
        }
        return nil
    }

    var availableOnboardingIdentifiers: [String] {
        pluginBundles.compactMap({ (bundle) -> String? in
            bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.onboardingIdentifier.rawValue) as? String
        })
    }

    func getSupportUITypeByIdentifier(_ identifier: String) -> SupportUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.supportIdentifier.rawValue) as? String,
               name == identifier
            {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {
                        if let plugin = principalClass.init() as? SupportUIPlugin {
                            return type(of: plugin.support)
                        } else {
                            fatalError("PrincipalClass does not conform to SupportUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch {
                    debug(.deviceManager, "Error loading plugin: \(error)")
                }
            }
        }
        return nil
    }
}

extension Bundle {
    var isPumpManagerPlugin: Bool {
        object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String != nil }

    var isCGMManagerPlugin: Bool {
        object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String != nil }

    var isStatefulPlugin: Bool {
        object(forInfoDictionaryKey: LoopPluginBundleKey.statefulPluginIdentifier.rawValue) as? String != nil }

    var isServicePlugin: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String != nil }
    var isOnboardingPlugin: Bool {
        object(forInfoDictionaryKey: LoopPluginBundleKey.onboardingIdentifier.rawValue) as? String != nil }

    var isSupportPlugin: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.supportIdentifier.rawValue) as? String != nil }

    var isLoopPlugin: Bool {
        isPumpManagerPlugin || isCGMManagerPlugin || isStatefulPlugin || isServicePlugin || isOnboardingPlugin || isSupportPlugin
    }

    var isLoopExtension: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.extensionIdentifier.rawValue) as? String != nil }

    var isSimulator: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.pluginIsSimulator.rawValue) as? Bool == true }
}
