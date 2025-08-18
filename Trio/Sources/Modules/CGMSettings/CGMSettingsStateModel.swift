import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI

/// For a full description of the events that can happen for the CGM lifecycle, see comment at the top
/// of HomeStateModel+CGM since these are the same events

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

extension CGMSettings {
    final class StateModel: BaseStateModel<Provider> {
        // Singleton implementation
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
        @Injected() var broadcaster: Broadcaster!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var bluetoothManager: BluetoothStateManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var shouldDisplayCGMSetupSheet: Bool = false
        @Published var cgmCurrent = cgmDefaultModel
        @Published var smoothGlucose = false
        @Published var cgmTransmitterDeviceAddress: String? = nil
        @Published var listOfCGM: [CGMModel] = []
        @Published var url: URL?

        var shouldRunDeleteOnSettingsChange = true

        override func subscribe() {
            units = settingsManager.settings.units
            broadcaster.register(SettingsObserver.self, observer: self)

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

        // this function will get called for all CGM types (plugin and non plugin)
        func addCGM(cgm: CGMModel) {
            cgmCurrent = cgm
            switch cgm.type {
            case .plugin:
                shouldDisplayCGMSetupSheet.toggle()
            default:
                // non plugin CGM types should be considered onboarded right away
                shouldDisplayCGMSetupSheet = true
                settingsManager.settings.cgm = cgmCurrent.type
                settingsManager.settings.cgmPluginIdentifier = ""
                fetchGlucoseManager.updateGlucoseSource(cgmGlucoseSourceType: cgmCurrent.type, cgmGlucosePluginId: cgmCurrent.id)
                broadcaster.notify(GlucoseObserver.self, on: .main) {
                    $0.glucoseDidUpdate([])
                }
            }
        }

        // Note: This function does _not_ get called for plugin CGMs
        // instead, they will get cgmManagerWantsDeletion events which
        // are handled by PluginSource
        func deleteCGM() {
            Task {
                await self.fetchGlucoseManager?.deleteGlucoseSource()

                await MainActor.run {
                    self.shouldDisplayCGMSetupSheet = false
                    broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate([])
                    }
                }
            }
        }
    }
}

extension CGMSettings.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task {
            // this sleep is because this event and cgmManagerWantsDeletion
            // are called in parallel.
            try await Task.sleep(for: .seconds(0.2))
            await MainActor.run {
                if fetchGlucoseManager.cgmGlucoseSourceType == .none {
                    cgmCurrent = cgmDefaultModel
                }
            }
        }
        shouldDisplayCGMSetupSheet = false
    }
}

extension CGMSettings.StateModel: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager manager: LoopKitUI.CGMManagerUI) {
        // cgmCurrent should have been set in addCGM
        debug(.service, "didCreateCGMManager called \(cgmCurrent)")
        settingsManager.settings.cgm = cgmCurrent.type
        settingsManager.settings.cgmPluginIdentifier = cgmCurrent.id
        fetchGlucoseManager.updateGlucoseSource(
            cgmGlucoseSourceType: cgmCurrent.type,
            cgmGlucosePluginId: cgmCurrent.id,
            newManager: manager
        )
        DispatchQueue.main.async {
            self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                $0.glucoseDidUpdate([])
            }
        }
    }

    func cgmManagerOnboarding(didOnboardCGMManager _: LoopKitUI.CGMManagerUI) {
        // nothing to do ?
    }
}

extension CGMSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
        // Deletes are handled differently for plugins vs non plugins
        // but both will call deleteGlucoseSource on the fetchGlucoseManager
        // so we listen for changes to the cgm setting and update our internal
        // state accordingly
        if settingsManager.settings.cgm == .none, shouldRunDeleteOnSettingsChange {
            shouldRunDeleteOnSettingsChange = false
            cgmCurrent = cgmDefaultModel
            DispatchQueue.main.async {
                self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                    $0.glucoseDidUpdate([])
                }
            }
        } else {
            shouldRunDeleteOnSettingsChange = true
        }
    }
}
