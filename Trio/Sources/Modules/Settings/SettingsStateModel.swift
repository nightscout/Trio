import LoopKit
import LoopKitUI
import SwiftUI
import TidepoolServiceKit

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() var pluginManager: PluginManager!
        @Injected() var fetchCgmManager: FetchGlucoseManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var closedLoop = false
        @Published var debugOptions = false
        @Published var serviceUIType: ServiceUI.Type?
        @Published var setupTidepool = false

        private(set) var buildNumber = ""
        private(set) var versionNumber = ""
        private(set) var branch = ""
        private(set) var copyrightNotice = ""

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.debugOptions, on: $debugOptions) { debugOptions = $0 }
            subscribeSetting(\.closedLoop, on: $closedLoop) { closedLoop = $0 }

            broadcaster.register(SettingsObserver.self, observer: self)

            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

            versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            branch = BuildDetails.shared.branchAndSha

            copyrightNotice = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

            serviceUIType = TidepoolService.self as? ServiceUI.Type
        }

        func logItems() -> [URL] {
            var items: [URL] = []

            if fileManager.fileExists(atPath: SimpleLogReporter.logFile) {
                items.append(URL(fileURLWithPath: SimpleLogReporter.logFile))
            }

            if fileManager.fileExists(atPath: SimpleLogReporter.logFilePrev) {
                items.append(URL(fileURLWithPath: SimpleLogReporter.logFilePrev))
            }

            return items
        }

        func hideSettingsModal() {
            hideModal()
        }

        // Commenting this out for now, as not needed and possibly dangerous for users to be able to nuke their pump pairing informations via the debug menu
        // Leaving it in here, as it may be a handy functionality for further testing or developers.
        // See https://github.com/nightscout/Trio/pull/277 for more information
//
//        func resetLoopDocuments() {
//            guard let localDocuments = try? FileManager.default.url(
//                for: .documentDirectory,
//                in: .userDomainMask,
//                appropriateFor: nil,
//                create: true
//            ) else {
//                preconditionFailure("Could not get a documents directory URL.")
//            }
//            let storageURL = localDocuments.appendingPathComponent("PumpManagerState" + ".plist")
//            try? FileManager.default.removeItem(at: storageURL)
//        }
        func hasCgmAndPump() -> Bool {
            let hasCgm = fetchCgmManager.cgmGlucoseSourceType != .none
            let hasPump = provider.deviceManager.pumpManager != nil
            return hasCgm && hasPump
        }
    }
}

extension Settings.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        closedLoop = settings.closedLoop
        debugOptions = settings.debugOptions
    }
}

extension Settings.StateModel: ServiceOnboardingDelegate {
    func serviceOnboarding(didCreateService service: Service) {
        debug(.nightscout, "Service with identifier \(service.pluginIdentifier) created")
        provider.tidepoolManager.addTidepoolService(service: service)
    }

    func serviceOnboarding(didOnboardService service: Service) {
        precondition(service.isOnboarded)
        debug(.nightscout, "Service with identifier \(service.pluginIdentifier) onboarded")
    }
}

extension Settings.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupTidepool = false
        provider.tidepoolManager.forceTidepoolDataUpload()
    }
}
