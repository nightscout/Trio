import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject
import UIKit

protocol FetchGlucoseManager: SourceInfoProvider {
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

    private let context = CoreDataStack.shared.newTaskContext()

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

    /// The function used to start the timer sync - Function of the variable defined in config
    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { [self] _ -> AnyPublisher<[BloodGlucose], Never> in
                debug(.nightscout, "FetchGlucoseManager timer heartbeat triggered")

                // Check if the glucose source is still available
                if let glucoseSource = self.glucoseSource {
                    debug(
                        .deviceManager,
                        "FetchGlucoseManager: glucoseSource exists, calling fetch() on source type: \(type(of: glucoseSource))"
                    )

                    // Check if we have a CGM manager when using a plugin source
                    if let pluginSource = glucoseSource as? PluginSource {
                        if pluginSource.cgmManager == nil {
                            debug(.deviceManager, "FetchGlucoseManager: WARNING - PluginSource has no CGM manager")
                        } else {
                            debug(
                                .deviceManager,
                                "FetchGlucoseManager: PluginSource has CGM manager of type: \(type(of: pluginSource.cgmManager!))"
                            )
                        }
                    }

                    return glucoseSource.fetch(self.timer)
                        .handleEvents(
                            receiveOutput: { values in
                                debug(.deviceManager, "FetchGlucoseManager: fetch() returned \(values.count) glucose values")
                                if !values.isEmpty {
                                    let firstValue = values.first!
                                    debug(
                                        .deviceManager,
                                        "FetchGlucoseManager: First glucose value: \(firstValue.glucose ?? 0) mg/dL at \(firstValue.dateString)"
                                    )
                                }
                            }
                        )
                        .eraseToAnyPublisher()
                } else {
                    debug(.deviceManager, "FetchGlucoseManager: No glucoseSource available, returning empty publisher")
                    return Empty(completeImmediately: false).eraseToAnyPublisher()
                }
            }
            .sink { glucose in
                debug(.nightscout, "FetchGlucoseManager callback received \(glucose.count) glucose values")
                let date = self.glucoseStorage.syncDate()
                debug(.deviceManager, "FetchGlucoseManager: sync date is \(date)")
                Publishers.CombineLatest(
                    Just(glucose),
                    Just(date)
                )
                .eraseToAnyPublisher()
                .sink { newGlucose, syncDate in
                    debug(
                        .deviceManager,
                        "FetchGlucoseManager: starting new task to invoke glucoseStoreAndHeartDecision with \(newGlucose.count) glucose values"
                    )
                    Task {
                        do {
                            try await self.glucoseStoreAndHeartDecision(
                                syncDate: syncDate,
                                glucose: newGlucose
                            )
                            debugPrint("\(#file) \(#function) glucoseStoreAndHeartDecision did complete")
                        } catch {
                            debug(.deviceManager, "Failed to store glucose: \(error.localizedDescription)")
                        }
                    }
                }
                .store(in: &self.lifetime)
            }
            .store(in: &lifetime)
        debug(.deviceManager, "FetchGlucoseManager: timer.fire() and timer.resume() called")
        timer.fire()
        timer.resume()
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
        debug(
            .deviceManager,
            "FetchGlucoseManager: updateGlucoseSource called with type: \(cgmGlucoseSourceType), pluginId: \(cgmGlucosePluginId), newManager: \(newManager != nil ? "provided" : "nil")"
        )

        // if changed, remove all calibrations
        if self.cgmGlucoseSourceType != cgmGlucoseSourceType || self.cgmGlucosePluginId != cgmGlucosePluginId {
            debug(
                .deviceManager,
                "FetchGlucoseManager: CGM type or plugin ID changed, removing calibrations and resetting managers"
            )
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
        debug(
            .deviceManager,
            "FetchGlucoseManager: Current plugin identifier: \(String(describing: cgmManager?.pluginIdentifier))"
        )

        if let manager = newManager {
            debug(.deviceManager, "FetchGlucoseManager: New manager provided of type: \(type(of: manager))")
            // If the pointer to manager is the *same* as our current `cgmManager`, skip re-init
            if manager !== cgmManager {
                debug(.deviceManager, "FetchGlucoseManager: New manager is different from current manager, reinitializing")
                // or do a more thorough check to see if it is the same class & state
                removeCalibrations()
                cgmManager = manager
                glucoseSource = nil
            } else {
                debug(
                    .deviceManager,
                    "FetchGlucoseManager: New manager is the same instance as current manager, skipping reinitialization"
                )
            }
        } else if self.cgmGlucoseSourceType == .plugin, cgmManager == nil, let rawCGMManager = rawCGMManager {
            debug(
                .deviceManager,
                "FetchGlucoseManager: Plugin type with no manager but raw state available, initializing from raw state"
            )
            cgmManager = cgmManagerFromRawValue(rawCGMManager)
            if cgmManager != nil {
                debug(
                    .deviceManager,
                    "FetchGlucoseManager: Successfully initialized CGM manager from raw state: \(type(of: cgmManager!))"
                )
            } else {
                debug(.deviceManager, "FetchGlucoseManager: Failed to initialize CGM manager from raw state")
            }
            updateManagerUnits(cgmManager)
        } else {
            debug(.deviceManager, "FetchGlucoseManager: No new manager provided, saving current configuration")
            saveConfigManager()
        }

        if glucoseSource == nil {
            debug(.deviceManager, "FetchGlucoseManager: Creating new glucose source for type: \(self.cgmGlucoseSourceType)")
            switch self.cgmGlucoseSourceType {
            case .none:
                debug(.deviceManager, "FetchGlucoseManager: Setting glucose source to nil for type .none")
                glucoseSource = nil
            case .xdrip:
                debug(.deviceManager, "FetchGlucoseManager: Creating AppGroupSource for xDrip")
                glucoseSource = AppGroupSource(from: "xDrip", cgmType: .xdrip)
            case .nightscout:
                debug(.deviceManager, "FetchGlucoseManager: Using nightscoutManager as glucose source")
                glucoseSource = nightscoutManager
            case .simulator:
                debug(.deviceManager, "FetchGlucoseManager: Creating simulator source")
                glucoseSource = simulatorSource
            case .enlite:
                debug(.deviceManager, "FetchGlucoseManager: Using deviceDataManager as glucose source")
                glucoseSource = deviceDataManager
            case .plugin:
                debug(.deviceManager, "FetchGlucoseManager: Creating PluginSource with current CGM manager")
                glucoseSource = PluginSource(glucoseStorage: glucoseStorage, glucoseManager: self)
            }

            if let source = glucoseSource {
                debug(.deviceManager, "FetchGlucoseManager: Successfully created glucose source of type: \(type(of: source))")
            } else {
                debug(.deviceManager, "FetchGlucoseManager: No glucose source created, source is nil")
            }
        } else {
            debug(.deviceManager, "FetchGlucoseManager: Keeping existing glucose source of type: \(type(of: glucoseSource!))")
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

    private func fetchGlucose() async throws -> [GlucoseStored]? {
        try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 6
        ) as? [GlucoseStored]
    }

    private func processGlucose() async throws -> [BloodGlucose] {
        let results = try await fetchGlucose()

        return try await context.perform {
            guard let results else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return results.map { result in
                BloodGlucose(
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose),
                    type: "sgv"
                )
            }
        }
    }

    private func glucoseStoreAndHeartDecision(syncDate: Date, glucose: [BloodGlucose]) async throws {
        // calibration add if required only for sensor
        let newGlucose = overcalibrate(entries: glucose)

        var filteredByDate: [BloodGlucose] = []
        var filtered: [BloodGlucose] = []

        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = startBackgroundTask(withName: "Glucose Store and Heartbeat Decision")

        guard newGlucose.isNotEmpty else {
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
            return
        }

        filteredByDate = newGlucose.filter { $0.dateString > syncDate }
        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

        guard filtered.isNotEmpty else {
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
            return
        }
        debug(.deviceManager, "New glucose found")

        // filter the data if it is the case
        if settingsManager.settings.smoothGlucose {
            // limited to 30 min of old glucose data
            let oldGlucoseValues = try await processGlucose()

            var smoothedValues = oldGlucoseValues + filtered
            // smooth with 3 repeats
            for _ in 1 ... 3 {
                smoothedValues.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
            }
            // find the new values only
            filtered = smoothedValues.filter { $0.dateString > syncDate }
        }

        try await glucoseStorage.storeGlucose(filtered)
        deviceDataManager.heartbeat(date: Date())

        endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
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
                guard entry.glucose != nil else { return entry }
                entry.glucose = Int(overcalibration(entry.glucose!))
                entry.sgv = Int(overcalibration(entry.sgv!))
                return entry
            }
        } else {
            return entries
        }
    }
}

extension FetchGlucoseManager {
    /// Dispatches given `functionToInvoke` to the CGM manager's queue (if any).
    func performOnCGMManagerQueue(_ functionToInvoke: @escaping () -> Void) {
        // If a CGM manager exists and it defines a delegate queue, use it
        if let cgmManager = self.cgmManager,
           let managerQueue = cgmManager.delegateQueue
        {
            managerQueue.async {
                functionToInvoke()
            }
        } else {
            // If there's no cgmManager or no queue, just run the block immediately
            // This possibly executes `functionToInvoke` on main thread
            functionToInvoke()
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
