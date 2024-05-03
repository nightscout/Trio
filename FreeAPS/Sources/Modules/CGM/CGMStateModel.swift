import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI

struct cgmName: Identifiable, Hashable {
    var id: String
    var type: CGMType
    var displayName: String
    var subtitle: String
}

let cgmDefaultName = cgmName(
    id: CGMType.none.id,
    type: .none,
    displayName: CGMType.none.displayName,
    subtitle: CGMType.none.subtitle
)

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var cgmManager: FetchGlucoseManager!
        @Injected() var calendarManager: CalendarManager!
        @Injected() var pluginCGMManager: PluginManager!
        @Injected() private var broadcaster: Broadcaster!
        @Injected() var nightscoutManager: NightscoutManager!

        @Published var setupCGM: Bool = false
        @Published var cgmCurrent = cgmDefaultName
        @Published var smoothGlucose = false
        @Published var createCalendarEvents = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil
        @Published var cgmTransmitterDeviceAddress: String? = nil
        @Published var listOfCGM: [cgmName] = []
        @Published var url: URL?

        override func subscribe() {
            // collect the list of CGM available with plugins and CGMType defined manually
            listOfCGM = CGMType.allCases.filter { $0 != CGMType.plugin }.map {
                cgmName(id: $0.id, type: $0, displayName: $0.displayName, subtitle: $0.subtitle)
            } +
                pluginCGMManager.availableCGMManagers.map {
                    cgmName(id: $0.identifier, type: CGMType.plugin, displayName: $0.localizedTitle, subtitle: $0.localizedTitle)
                }

            switch settingsManager.settings.cgm {
            case .plugin:
                if let cgmPluginInfo = listOfCGM.first(where: { $0.id == settingsManager.settings.cgmPluginIdentifier }) {
                    cgmCurrent = cgmName(
                        id: settingsManager.settings.cgmPluginIdentifier,
                        type: .plugin,
                        displayName: cgmPluginInfo.displayName,
                        subtitle: cgmPluginInfo.subtitle
                    )
                } else {
                    // no more type of plugin available - restart to defaut
                    cgmCurrent = cgmDefaultName
                }
            default:
                cgmCurrent = cgmName(
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

            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = calendarManager.calendarIDs()
            cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress

            subscribeSetting(\.useCalendar, on: $createCalendarEvents) { createCalendarEvents = $0 }
            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })

            $cgmCurrent
                .removeDuplicates()
                .sink { [weak self] value in
                    guard let self = self else { return }
                    guard self.cgmManager.cgmGlucoseSourceType != nil else {
                        self.settingsManager.settings.cgm = .none
                        return
                    }
                    if value.type != self.settingsManager.settings.cgm ||
                        value.id != self.settingsManager.settings.cgmPluginIdentifier
                    {
                        self.settingsManager.settings.cgm = value.type
                        self.settingsManager.settings.cgmPluginIdentifier = value.id
                        self.cgmManager.updateGlucoseSource(
                            cgmGlucoseSourceType: value.type,
                            cgmGlucosePluginId: value.id
                        )
                        self.setupCGM = false
                    }
                }
                .store(in: &lifetime)

            $createCalendarEvents
                .removeDuplicates()
                .flatMap { [weak self] ok -> AnyPublisher<Bool, Never> in
                    guard ok, let self = self else { return Just(false).eraseToAnyPublisher() }
                    return self.calendarManager.requestAccessIfNeeded()
                }
                .map { [weak self] ok -> [String] in
                    guard ok, let self = self else { return [] }
                    return self.calendarManager.calendarIDs()
                }
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.calendarIDs, on: self)
                .store(in: &lifetime)

            $currentCalendarID
                .removeDuplicates()
                .sink { [weak self] id in
                    guard id.isNotEmpty else {
                        self?.calendarManager.currentCalendarID = nil
                        return
                    }
                    self?.calendarManager.currentCalendarID = id
                }
                .store(in: &lifetime)
        }

        func displayNameOfApp() -> String {
            var nameOfApp = "Open Application"
            switch cgmManager.cgmGlucoseSourceType {
            case .plugin:
                nameOfApp = "Open " + (cgmManager.cgmManager?.localizedTitle ?? "Application")
            default:
                nameOfApp = "Open " + (cgmManager.cgmGlucoseSourceType.displayName ?? "Application")
            }
            return nameOfApp
        }

        func urlOfApp() -> URL? {
            switch cgmManager.cgmGlucoseSourceType {
            case .plugin:
                return cgmManager.cgmManager?.appURL
            default:
                return cgmManager.cgmGlucoseSourceType.appURL
            }
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupCGM = false

        // if CGM was deleted
        if cgmManager.cgmGlucoseSourceType == nil {
            cgmCurrent = cgmDefaultName
            settingsManager.settings.cgm = cgmDefaultName.type
            settingsManager.settings.cgmPluginIdentifier = cgmDefaultName.id
            cgmManager.deleteGlucoseSource()
        } else {
            cgmManager.updateGlucoseSource(cgmGlucoseSourceType: cgmCurrent.type, cgmGlucosePluginId: cgmCurrent.id)
        }

        // update if required the Glucose source
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
