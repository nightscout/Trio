import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI

struct CGMModel: Identifiable, Hashable {
    var id: String
    var type: CGMType
    var displayName: String
    var subtitle: String
}

struct CGMOption {
    let name: String
    let predicate: (CGMModel) -> Bool
}

let cgmDefaultModel = CGMModel(
    id: CGMType.none.id,
    type: .none,
    displayName: CGMType.none.displayName,
    subtitle: CGMType.none.subtitle
)

struct EmptyCompletionNotifying: CompletionNotifying {
    var completionDelegate: (any LoopKitUI.CompletionDelegate)?
}

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var cgmManager: FetchGlucoseManager!
        @Injected() var pluginCGMManager: PluginManager!
        @Injected() private var broadcaster: Broadcaster!
        @Injected() var nightscoutManager: NightscoutManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var shouldDisplayCGMSetupSheet: Bool = false
        @Published var cgmCurrent = cgmDefaultModel
        @Published var smoothGlucose = false
        @Published var cgmTransmitterDeviceAddress: String? = nil
        @Published var listOfCGM: [CGMModel] = []
        @Published var url: URL?

        override func subscribe() {
            units = settingsManager.settings.units

            // collect the list of CGM available with plugins and CGMType defined manually
            listOfCGM = (
                CGMType.allCases.filter { $0 != CGMType.plugin }.map {
                    CGMModel(id: $0.id, type: $0, displayName: $0.displayName, subtitle: $0.subtitle)
                } +
                    pluginCGMManager.availableCGMManagers.map {
                        CGMModel(
                            id: $0.identifier,
                            type: CGMType.plugin,
                            displayName: $0.localizedTitle,
                            subtitle: $0.localizedTitle
                        )
                    }
            ).sorted(by: { lhs, rhs in
                if lhs.displayName == "None" {
                    return true
                } else if rhs.displayName == "None" {
                    return false
                } else {
                    return lhs.displayName < rhs.displayName
                }
            })

            switch settingsManager.settings.cgm {
            case .plugin:
                if let cgmPluginInfo = listOfCGM.first(where: { $0.id == settingsManager.settings.cgmPluginIdentifier }) {
                    cgmCurrent = CGMModel(
                        id: settingsManager.settings.cgmPluginIdentifier,
                        type: .plugin,
                        displayName: cgmPluginInfo.displayName,
                        subtitle: cgmPluginInfo.subtitle
                    )
                } else {
                    // no more type of plugin available - restart to defaut
                    cgmCurrent = cgmDefaultModel
                }
            default:
                cgmCurrent = CGMModel(
                    id: settingsManager.settings.cgm.id,
                    type: settingsManager.settings.cgm,
                    displayName: settingsManager.settings.cgm.displayName,
                    subtitle: settingsManager.settings.cgm.subtitle
                )
            }

            url = nightscoutManager.cgmURL
            switch url?.absoluteString {
            case "http://127.0.0.1:1979":
                url = URL(string: "spikeapp://")!
            case "http://127.0.0.1:17580":
                url = URL(string: "diabox://")!
            //            case CGMType.libreTransmitter.appURL?.absoluteString:
            //                showModal(for: .libreConfig)
            default: break
            }

            cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress

            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })
        }

        func displayNameOfApp() -> String? {
            guard cgmManager != nil else { return nil }
            var nameOfApp = "Open Application"
            switch cgmManager.cgmGlucoseSourceType {
            case .plugin:
                nameOfApp = "Open " + (cgmManager.cgmManager?.localizedTitle ?? "Application")
            default:
                nameOfApp = "Open " + cgmManager.cgmGlucoseSourceType.displayName
            }
            return nameOfApp
        }

        func urlOfApp() -> URL? {
            guard cgmManager != nil else { return nil }
            switch cgmManager.cgmGlucoseSourceType {
            case .plugin:
                return cgmManager.cgmManager?.appURL
            default:
                return cgmManager.cgmGlucoseSourceType.appURL
            }
        }

        func addCGM(cgm: CGMModel) {
            cgmCurrent = cgm
            switch cgmCurrent.type {
            case .plugin:
                shouldDisplayCGMSetupSheet.toggle()
            default:
                cgmManager.cgmGlucoseSourceType = cgmCurrent.type
                completionNotifyingDidComplete(EmptyCompletionNotifying())
            }
        }

        func deleteCGM() {
            shouldDisplayCGMSetupSheet = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                self.cgmManager.deleteGlucoseSource()
                self.completionNotifyingDidComplete(EmptyCompletionNotifying())
            })
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        shouldDisplayCGMSetupSheet = false

        // if CGM was deleted
        if cgmManager.cgmGlucoseSourceType == .none {
            cgmCurrent = cgmDefaultModel
            settingsManager.settings.cgm = cgmDefaultModel.type
            settingsManager.settings.cgmPluginIdentifier = cgmDefaultModel.id
            cgmManager.deleteGlucoseSource()
        } else {
            settingsManager.settings.cgm = cgmCurrent.type
            settingsManager.settings.cgmPluginIdentifier = cgmCurrent.id
            cgmManager.updateGlucoseSource(cgmGlucoseSourceType: cgmCurrent.type, cgmGlucosePluginId: cgmCurrent.id)
        }

        // update glucose source if required
        DispatchQueue.main.async {
            self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                $0.glucoseDidUpdate([])
            }
        }
    }
}

extension CGM.StateModel: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager manager: LoopKitUI.CGMManagerUI) {
        // update the glucose source
        cgmManager.updateGlucoseSource(
            cgmGlucoseSourceType: cgmCurrent.type,
            cgmGlucosePluginId: cgmCurrent.id,
            newManager: manager
        )
    }

    func cgmManagerOnboarding(didOnboardCGMManager _: LoopKitUI.CGMManagerUI) {
        // nothing to do ?
    }
}

extension CGM.StateModel {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
