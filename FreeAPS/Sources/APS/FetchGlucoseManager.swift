import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject
import UIKit

protocol FetchGlucoseManager: SourceInfoProvider {
    func updateGlucoseStore(newBloodGlucose: [BloodGlucose])
    func refreshCGM()
    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String, newManager: CGMManagerUI?)
    func deleteGlucoseSource()
    func removeCalibrations()
    var glucoseSource: GlucoseSource! { get }
    var cgmManager: CGMManagerUI? { get }
    var cgmGlucoseSourceType: CGMType { get set }
    var cgmGlucosePluginId: String { get }
    var settingsManager: SettingsManager! { get }
    var shouldSyncToRemoteService: Bool { get }
}

extension FetchGlucoseManager {
    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String) {
        updateGlucoseSource(cgmGlucoseSourceType: cgmGlucoseSourceType, cgmGlucosePluginId: cgmGlucosePluginId, newManager: nil)
    }
}

final class BaseFetchGlucoseManager: FetchGlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var tidepoolService: TidepoolManager!
    @Injected() var apsManager: APSManager!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var healthKitManager: HealthKitManager!
    @Injected() var deviceDataManager: DeviceDataManager!
    @Injected() var pluginCGMManager: PluginManager!
    @Injected() var calibrationService: CalibrationService!

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)
    var cgmGlucoseSourceType: CGMType = .none
    var cgmGlucosePluginId: String = ""
    var cgmManager: CGMManagerUI? {
        didSet {
            rawCGMManager = cgmManager?.rawValue
            UserDefaults.standard.clearLegacyCGMManagerRawValue()
        }
    }

    @PersistedProperty(key: "CGMManagerState") var rawCGMManager: CGMManager.RawValue?

    private lazy var simulatorSource = GlucoseSimulatorSource()

    var shouldSyncToRemoteService: Bool {
        guard let cgmManager = cgmManager else {
            return true
        }
        return cgmManager.shouldSyncToRemoteService
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        // init at the start of the app
        cgmGlucoseSourceType = settingsManager.settings.cgm
        cgmGlucosePluginId = settingsManager.settings.cgmPluginIdentifier
        // load cgmManager
        updateGlucoseSource(
            cgmGlucoseSourceType: settingsManager.settings.cgm,
            cgmGlucosePluginId: settingsManager.settings.cgmPluginIdentifier
        )
        subscribe()
    }

    var glucoseSource: GlucoseSource!

    func removeCalibrations() {
        calibrationService.removeAllCalibrations()
    }

    func deleteGlucoseSource() {
        cgmManager = nil
        updateGlucoseSource(
            cgmGlucoseSourceType: CGMType.none,
            cgmGlucosePluginId: ""
        )
    }

    func saveConfigManager() {
        guard let cgmM = cgmManager else {
            return
        }
        // save the config in rawCGMManager
        rawCGMManager = cgmM.rawValue

        // sync with upload glucose
        settingsManager.settings.uploadGlucose = cgmM.shouldSyncToRemoteService
    }

    private func updateManagerUnits(_ manager: CGMManagerUI?) {
        let units = settingsManager.settings.units
        let managerName = cgmManager.map { "\(type(of: $0))" } ?? "nil"
        let loopkitUnits: HKUnit = units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter
        print("manager: \(managerName) is changing units to: \(loopkitUnits.description) ")
        manager?.unitDidChange(to: loopkitUnits)
    }

    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String, newManager: CGMManagerUI?) {
        // if changed, remove all calibrations
        if self.cgmGlucoseSourceType != cgmGlucoseSourceType || self.cgmGlucosePluginId != cgmGlucosePluginId {
            removeCalibrations()
            cgmManager = nil
            glucoseSource = nil
        }

        self.cgmGlucoseSourceType = cgmGlucoseSourceType
        self.cgmGlucosePluginId = cgmGlucosePluginId

        // if not plugin, manager is not changed and stay with the "old" value if the user come back to previous cgmtype
        // if plugin, if the same pluginID, no change required because the manager is available
        // if plugin, if not the same pluginID, need to reset the cgmManager
        // if plugin and newManager provides, update cgmManager
        debug(.apsManager, "plugin : \(String(describing: cgmManager?.pluginIdentifier))")
        if let manager = newManager
        {
            cgmManager = manager
            removeCalibrations()
        } else if self.cgmGlucoseSourceType == .plugin, cgmManager == nil, let rawCGMManager = rawCGMManager {
            cgmManager = cgmManagerFromRawValue(rawCGMManager)
            updateManagerUnits(cgmManager)

        } else {
            saveConfigManager()
        }

        if glucoseSource == nil {
            switch self.cgmGlucoseSourceType {
            case .none:
                glucoseSource = nil
            case .xdrip:
                glucoseSource = AppGroupSource(from: "xDrip", cgmType: .xdrip)
            case .nightscout:
                glucoseSource = nightscoutManager
            case .simulator:
                glucoseSource = simulatorSource
            case .glucoseDirect:
                glucoseSource = AppGroupSource(from: "GlucoseDirect", cgmType: .glucoseDirect)
            case .enlite:
                glucoseSource = deviceDataManager
            case .plugin:
                glucoseSource = PluginSource(glucoseStorage: glucoseStorage, glucoseManager: self)
            }
        }
    }

    /// Upload cgmManager from raw value
    func cgmManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManagerUI? {
        guard let rawState = rawValue["state"] as? CGMManager.RawStateValue,
              let Manager = pluginCGMManager.getCGMManagerTypeByIdentifier(cgmGlucosePluginId)
        else {
            return nil
        }
        return Manager.init(rawState: rawState)
    }

    /// function called when a callback is fired by CGM BLE - no more used
    public func updateGlucoseStore(newBloodGlucose: [BloodGlucose]) {
        let syncDate = glucoseStorage.syncDate()
        debug(.deviceManager, "CGM BLE FETCHGLUCOSE  : SyncDate is \(syncDate)")
        glucoseStoreAndHeartDecision(syncDate: syncDate, glucose: newBloodGlucose)
    }

    /// function to try to force the refresh of the CGM - generally provide by the pump heartbeat
    public func refreshCGM() {
        debug(.deviceManager, "refreshCGM by pump")
        // updateGlucoseSource(cgmGlucoseSourceType: settingsManager.settings.cgm, cgmGlucosePluginId: settingsManager.settings.cgmPluginIdentifier)

        Publishers.CombineLatest3(
            Just(glucoseStorage.syncDate()),
            healthKitManager.fetch(nil),
            glucoseSource.fetchIfNeeded()
        )
        .eraseToAnyPublisher()
        .receive(on: processQueue)
        .sink { syncDate, glucoseFromHealth, glucose in
            debug(.nightscout, "refreshCGM FETCHGLUCOSE : SyncDate is \(syncDate)")
            self.glucoseStoreAndHeartDecision(syncDate: syncDate, glucose: glucose, glucoseFromHealth: glucoseFromHealth)
        }
        .store(in: &lifetime)
    }

    private func glucoseStoreAndHeartDecision(syncDate: Date, glucose: [BloodGlucose], glucoseFromHealth: [BloodGlucose] = []) {
        // calibration add if required only for sensor
        let newGlucose = overcalibrate(entries: glucose)

        let allGlucose = newGlucose + glucoseFromHealth
        var filteredByDate: [BloodGlucose] = []
        var filtered: [BloodGlucose] = []

        // start background time extension
        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
            guard let bg = backGroundFetchBGTaskID else { return }
            UIApplication.shared.endBackgroundTask(bg)
            backGroundFetchBGTaskID = .invalid
        }

        guard allGlucose.isNotEmpty else {
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return
        }

        filteredByDate = allGlucose.filter { $0.dateString > syncDate }
        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

        guard filtered.isNotEmpty else {
            // end of the BG tasks
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return
        }
        debug(.deviceManager, "New glucose found")

        // filter the data if it is the case
        if settingsManager.settings.smoothGlucose {
            // limit to 30 minutes of previous BG Data
            let oldGlucoses = glucoseStorage.recent().filter {
                $0.dateString.addingTimeInterval(31 * 60) > Date()
            }
            var smoothedValues = oldGlucoses + filtered
            // smooth with 3 repeats
            for _ in 1 ... 3 {
                smoothedValues.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
            }
            // find the new values only
            filtered = smoothedValues.filter { $0.dateString > syncDate }
        }

        glucoseStorage.storeGlucose(filtered)

        deviceDataManager.heartbeat(date: Date())

        nightscoutManager.uploadGlucose()
        tidepoolService.uploadGlucose(device: cgmManager?.cgmManagerStatus.device)

        let glucoseForHealth = filteredByDate.filter { !glucoseFromHealth.contains($0) }

        guard glucoseForHealth.isNotEmpty else {
            // end of the BG tasks
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return
        }
        healthKitManager.saveIfNeeded(bloodGlucose: glucoseForHealth)

        // end of the BG tasks
        if let backgroundTask = backGroundFetchBGTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backGroundFetchBGTaskID = .invalid
        }
    }

    /// The function used to start the timer sync - Function of the variable defined in config
    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { [self] _ -> AnyPublisher<[BloodGlucose], Never> in
                debug(.nightscout, "FetchGlucoseManager timer heartbeat")
                if let glucoseSource = self.glucoseSource {
                    return glucoseSource.fetch(self.timer).eraseToAnyPublisher()
                } else {
                    return Empty(completeImmediately: false).eraseToAnyPublisher()
                }
            }
            .sink { glucose in
                debug(.nightscout, "FetchGlucoseManager callback sensor")
                Publishers.CombineLatest3(
                    Just(glucose),
                    Just(self.glucoseStorage.syncDate()),
                    self.healthKitManager.fetch(nil)
                )
                .eraseToAnyPublisher()
                .sink { newGlucose, syncDate, glucoseFromHealth in
                    self.glucoseStoreAndHeartDecision(
                        syncDate: syncDate,
                        glucose: newGlucose,
                        glucoseFromHealth: glucoseFromHealth
                    )
                }
                .store(in: &self.lifetime)
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }

    func sourceInfo() -> [String: Any]? {
        glucoseSource.sourceInfo()
    }

    private func overcalibrate(entries: [BloodGlucose]) -> [BloodGlucose] {
        // overcalibrate
        var overcalibration: ((Int) -> (Double))?

        if let cal = calibrationService {
            overcalibration = cal.calibrate
        }

        if let overcalibration = overcalibration {
            return entries.map { entry in
                var entry = entry
                entry.glucose = Int(overcalibration(entry.glucose!))
                entry.sgv = Int(overcalibration(entry.sgv!))
                return entry
            }
        } else {
            return entries
        }
    }
}

extension CGMManager {
    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        [
            "managerIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}
