import CGMBLEKit
import Combine
import Foundation
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

extension CGMModel {
    init(_ entry: CGMCatalogEntry) {
        self.init(id: entry.id, type: entry.cgmType, displayName: entry.name, subtitle: entry.subtitle)
    }
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
        // Rich xDrip4iOS information is optional and does not replace the normal glucose data flow.
        @Published var xDripCGMInformation: AppGroupCGMInformation?
        @Published var listOfCGM: [CGMModel] = []
        @Published var url: URL?

        var shouldRunDeleteOnSettingsChange = true
        private var xDripInformationSubscription: AnyCancellable?

        override func subscribe() {
            units = settingsManager.settings.units
            broadcaster.register(SettingsObserver.self, observer: self)

            listOfCGM = DeviceCatalog.cgmModels

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

            // The app-group source may already contain a snapshot from an earlier fetch.
            subscribeToXDripInformation()

            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })
        }

        // this function will get called for all CGM types (plugin and non plugin)
        func addCGM(cgm: CGMModel) {
            cgmCurrent = cgm
            switch cgm.type {
            case .plugin:
                // Not toggle(): addCGM is now invoked from a sheet's onDismiss, where a stale true would close
                // the setup sheet instead of opening it.
                shouldDisplayCGMSetupSheet = true
            default:
                // non plugin CGM types should be considered onboarded right away
                shouldDisplayCGMSetupSheet = true
                settingsManager.settings.cgm = cgmCurrent.type
                settingsManager.settings.cgmPluginIdentifier = ""
                fetchGlucoseManager.updateGlucoseSource(cgmGlucoseSourceType: cgmCurrent.type, cgmGlucosePluginId: cgmCurrent.id)
                // Reconnect after changing CGM because updateGlucoseSource replaces the source instance.
                subscribeToXDripInformation()
                broadcaster.notify(GlucoseObserver.self, on: .main) {
                    $0.glucoseDidUpdate([])
                }
            }
        }

        private func subscribeToXDripInformation() {
            // Dropping the old subscription also prevents information from the previous source leaking into this view.
            xDripInformationSubscription = nil
            guard let source = fetchGlucoseManager.glucoseSource as? AppGroupSource else {
                xDripCGMInformation = nil
                return
            }
            xDripCGMInformation = source.cgmInformation.value
            xDripInformationSubscription = source.cgmInformation
                .receive(on: DispatchQueue.main)
                .sink { [weak self] information in self?.xDripCGMInformation = information }
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

// Combines the useful metadata fields with the readings already accepted by AppGroupSource.
struct AppGroupCGMInformation {
    struct RecentReading: Identifiable {
        let date: Date
        let glucoseMgDl: Int

        var id: Date { date }
    }

    struct Producer {
        let appName: String?
        let version: String?
    }

    struct Sensor {
        let state: String?
        let type: String?
        let model: String?
        let serialNumber: String?
        let startedAt: Date?
        let warmupEndsAt: Date?
        let expiresAt: Date?
        let graceEndsAt: Date?
    }

    struct LatestData {
        let qualityCode: String
    }

    struct Transmitter {
        struct Battery {
            let value: Double
            let unit: String?
        }

        let identifier: String?
        let battery: Battery?
    }

    struct Calibration {
        let state: String
    }

    let producer: Producer?
    let sensor: Sensor?
    let latestData: LatestData?
    let transmitter: Transmitter?
    let calibration: Calibration?
    let recentReadings: [RecentReading]

    // Grace, when supplied, is the real end of the complete sensor lifecycle.
    var lifecycleEnd: Date? { sensor?.graceEndsAt ?? sensor?.expiresAt }
}

// Decode defensively because xDrip4iOS and Trio can be upgraded or downgraded independently.
enum AppGroupCGMMetadataDecoder {
    static let appGroupKey = "xDrip4iOSCGMMetadata"
    static let supportedSchemaVersion = 1
    static let futureTolerance: TimeInterval = .minutes(5)
    static let writeOrderTolerance: TimeInterval = 5

    static func decode(
        sharedDefaults: UserDefaults,
        readings: [AnyObject],
        source: String,
        parseDate: (String) -> Date?
    ) -> AppGroupCGMInformation? {
        // Use the exact readings Trio received so the history and latest value cannot disagree.
        let recentReadings = readings.compactMap { reading -> AppGroupCGMInformation.RecentReading? in
            if let readingSource = reading["from"] as? String, readingSource != source { return nil }
            guard let timestamp = reading["DT"] as? String,
                  let date = parseDate(timestamp),
                  let glucose = (reading["Value"] as? NSNumber)?.intValue
            else { return nil }
            return .init(date: date, glucoseMgDl: glucose)
        }
        .sorted { $0.date > $1.date }

        // No envelope is the normal readings-only behavior for an older producer.
        guard let data = sharedDefaults.data(forKey: appGroupKey),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = integer(root["schemaVersion"]),
              schemaVersion == supportedSchemaVersion,
              let generatedAt = date(root["generatedAt"]),
              generatedAt <= Date().addingTimeInterval(futureTolerance)
        else { return nil }

        // An older producer may leave this additive key behind, so a newer legacy reading makes the envelope obsolete.
        if let newestReadingAt = recentReadings.first?.date,
           newestReadingAt > generatedAt.addingTimeInterval(writeOrderTolerance)
        {
            return nil
        }

        // Treat every section as optional so one malformed section does not hide the remaining useful information.
        let producer = dictionary(root["producer"]).map {
            AppGroupCGMInformation.Producer(
                appName: string($0["appName"]),
                version: string($0["version"])
            )
        }
        let sensor: AppGroupCGMInformation.Sensor? = dictionary(root["sensor"]).flatMap {
            let sensor = AppGroupCGMInformation.Sensor(
                state: string($0["state"]),
                type: string($0["type"]),
                model: string($0["model"]),
                serialNumber: string($0["serialNumber"]),
                startedAt: date($0["startedAt"]),
                warmupEndsAt: date($0["warmupEndsAt"]),
                expiresAt: date($0["expiresAt"]),
                graceEndsAt: date($0["graceEndsAt"])
            )
            guard sensor.state != nil || sensor.type != nil || sensor.model != nil || sensor.serialNumber != nil ||
                sensor.startedAt != nil || sensor.warmupEndsAt != nil || sensor.expiresAt != nil || sensor.graceEndsAt != nil
            else { return nil }
            return sensor
        }
        let latestData = dictionary(root["latestData"]).flatMap {
            string($0["qualityCode"]).map(AppGroupCGMInformation.LatestData.init)
        }
        let transmitter: AppGroupCGMInformation.Transmitter? = dictionary(root["transmitter"]).flatMap { transmitter in
            let battery: AppGroupCGMInformation.Transmitter.Battery? = dictionary(transmitter["battery"]).flatMap {
                guard let value = number($0["value"]) else { return nil }
                return AppGroupCGMInformation.Transmitter.Battery(value: value, unit: string($0["unit"]))
            }
            let identifier = string(transmitter["identifier"])
            guard identifier != nil || battery != nil else { return nil }
            return AppGroupCGMInformation.Transmitter(identifier: identifier, battery: battery)
        }
        let calibration = dictionary(root["calibration"]).flatMap {
            string($0["state"]).map(AppGroupCGMInformation.Calibration.init)
        }

        // Do not associate retained readings from the previous sensor with the current metadata.
        let associatedReadings = sensor?.startedAt.map { start in
            recentReadings.filter { $0.date >= start }
        } ?? recentReadings
        return AppGroupCGMInformation(
            producer: producer,
            sensor: sensor,
            latestData: latestData,
            transmitter: transmitter,
            calibration: calibration,
            recentReadings: associatedReadings
        )
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private static func string(_ value: Any?) -> String? { value as? String }
    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private static func integer(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private static func date(_ value: Any?) -> Date? { number(value).map(Date.init(timeIntervalSince1970:)) }
}
