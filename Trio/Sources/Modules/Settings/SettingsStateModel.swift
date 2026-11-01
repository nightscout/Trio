import CoreData
import Foundation
import LoopKit
import LoopKitUI
import SwiftUI
import TidepoolServiceKit

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() var logExport: LogExport!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() var pluginManager: PluginManager!
        @Injected() var fetchCgmManager: FetchGlucoseManager!
        @Injected() private var storage: FileStorage!
        @Injected() var overrideStorage: OverrideStorage!
        @Injected() private var keychain: Keychain!

        @Published var units: GlucoseUnits = .mgdL
        @Published var dosingMode: DosingMode = .open
        @Published var debugOptions = false
        @Published var serviceUIType: ServiceUI.Type?
        @Published var setupTidepool = false

        private(set) var buildNumber = ""
        private(set) var versionNumber = ""
        private(set) var branch = ""
        private(set) var copyrightNotice = ""
        private(set) var reportSubmitter: ReportSubmitting?

        override func subscribe() {
            units = settingsManager.settings.units
            reportSubmitter = ReportEndpoint.submitter(keychain: keychain)

            subscribeSetting(\.debugOptions, on: $debugOptions) { debugOptions = $0 }
            subscribeSetting(\.dosingMode, on: $dosingMode) { dosingMode = $0 }
            broadcaster.register(SettingsObserver.self, observer: self)

            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

            versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            branch = BuildDetails.shared.branchAndSha

            copyrightNotice = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

            serviceUIType = TidepoolService.self as? ServiceUI.Type
        }

        var logKinds: [LogExport.Kind] {
            var kinds: [LogExport.Kind] = [.all]
            // Read during the first render, before the resolver is set
            if provider?.deviceManager?.pumpManager != nil {
                kinds.append(.pump)
            }
            if let fetchCgmManager, fetchCgmManager.cgmGlucoseSourceType == .plugin, fetchCgmManager.cgmManager != nil {
                kinds.append(.cgm)
            }
            return kinds
        }

        func reportContext() -> ProblemReport.Context {
            var cgm: String?
            if let source = fetchCgmManager?.cgmGlucoseSourceType, source != .none {
                cgm = source == .plugin ? fetchCgmManager?.cgmManager?.localizedTitle : source.displayName
            }
            return .current(pump: provider?.deviceManager?.pumpManager?.localizedTitle, cgm: cgm)
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
        dosingMode = settings.dosingMode
        debugOptions = settings.debugOptions
    }
}

extension Settings.StateModel: ServiceOnboardingDelegate {
    func serviceOnboarding(didCreateService service: Service) {
        info(.settings, "Service \(service.pluginIdentifier) added")
        provider.tidepoolManager.addTidepoolService(service: service)
    }

    func serviceOnboarding(didOnboardService service: Service) {
        precondition(service.isOnboarded)
        debug(.settings, "Service \(service.pluginIdentifier) onboarded")
    }
}

extension Settings.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupTidepool = false
        provider.tidepoolManager.forceTidepoolDataUpload()
    }
}
