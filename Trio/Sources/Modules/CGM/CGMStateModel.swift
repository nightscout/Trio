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

struct OtherCGMSourceCompletionNotifying: CompletionNotifying {
    var completionDelegate: (any LoopKitUI.CompletionDelegate)?
}

class CGMSetupCompletionNotifying: CompletionNotifying {
    var completionDelegate: (any LoopKitUI.CompletionDelegate)?
}

class CGMDeletionCompletionNotifying: CompletionNotifying {
    var completionDelegate: (any LoopKitUI.CompletionDelegate)?
}

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        private static var _shared: StateModel?
        static var shared: StateModel {
            if _shared == nil {
                _shared = StateModel()
                _shared?.resolver = TrioApp().resolver
            }
            return _shared!
        }

        @Injected() var fetchGlucoseManager: FetchGlucoseManager!
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
                    // no more type of plugin available - fallback to default model
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
            default: break
            }

            cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress

            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })
        }

        func addCGM(cgm: CGMModel) {
            cgmCurrent = cgm
            switch cgmCurrent.type {
            case .plugin:
                shouldDisplayCGMSetupSheet.toggle()
            default:
                fetchGlucoseManager.cgmGlucoseSourceType = cgmCurrent.type
                completionNotifyingDidComplete(OtherCGMSourceCompletionNotifying())
            }
        }

        func deleteCGM() {
            shouldDisplayCGMSetupSheet = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                self.fetchGlucoseManager.deleteGlucoseSource()
                self.completionNotifyingDidComplete(OtherCGMSourceCompletionNotifying())
            })
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        // if CGM was deleted
        if fetchGlucoseManager.cgmGlucoseSourceType == .none {
            cgmCurrent = cgmDefaultModel
            settingsManager.settings.cgm = cgmDefaultModel.type
            settingsManager.settings.cgmPluginIdentifier = cgmDefaultModel.id
            fetchGlucoseManager.deleteGlucoseSource()
            shouldDisplayCGMSetupSheet = false
        } else {
            settingsManager.settings.cgm = cgmCurrent.type
            settingsManager.settings.cgmPluginIdentifier = cgmCurrent.id
            fetchGlucoseManager.updateGlucoseSource(cgmGlucoseSourceType: cgmCurrent.type, cgmGlucosePluginId: cgmCurrent.id)
            shouldDisplayCGMSetupSheet = cgmCurrent.type == .simulator || cgmCurrent.type == .nightscout || cgmCurrent
                .type == .xdrip || cgmCurrent.type == .enlite
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
        fetchGlucoseManager.updateGlucoseSource(
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
