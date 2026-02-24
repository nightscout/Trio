import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject
import UIKit

protocol FetchGlucoseManager: SourceInfoProvider {
    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String, newManager: CGMManagerUI?)
    func deleteGlucoseSource() async
    func removeCalibrations()
    func newGlucoseFromCgmManager(newGlucose: [BloodGlucose])
    var glucoseSource: GlucoseSource? { get }
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

    @Injected() var broadcaster: Broadcaster!
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

    /// Enforce mutual exclusion on calls to glucoseStoreAndHeartDecision
    private let glucoseStoreAndHeartLock = DispatchSemaphore(value: 1)

    var shouldSyncToRemoteService: Bool {
        guard let cgmManager = cgmManager else {
            return true
        }
        return cgmManager.shouldSyncToRemoteService
    }

    var shouldSmoothGlucose: Bool = false

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
        shouldSmoothGlucose = settingsManager.settings.smoothGlucose
        subscribe()
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
                Publishers.CombineLatest(
                    Just(glucose),
                    Just(self.glucoseStorage.syncDate())
                )
                .eraseToAnyPublisher()
                .sink { newGlucose, syncDate in
                    self.glucoseStoreAndHeartLock.wait()
                    Task {
                        do {
                            try await self.glucoseStoreAndHeartDecision(
                                syncDate: syncDate,
                                glucose: newGlucose
                            )
                        } catch {
                            debug(.deviceManager, "Failed to store glucose: \(error)")
                        }
                        self.glucoseStoreAndHeartLock.signal()
                    }
                }
                .store(in: &self.lifetime)
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()

        broadcaster.register(SettingsObserver.self, observer: self)
    }

    /// Store new glucose readings from the CGM manager
    ///
    /// This function enables plugin CGM managers to send new glucose readings directly
    /// to the FetchGlucoseManager, bypassing the Combine pipeline. By bypassing the
    /// Combine pipeline CGM managers can send backfill glucose readings, which come
    /// right after a new glucose reading, typically.
    func newGlucoseFromCgmManager(newGlucose: [BloodGlucose]) {
        glucoseStoreAndHeartLock.wait()
        let syncDate = glucoseStorage.syncDate()
        Task {
            do {
                try await glucoseStoreAndHeartDecision(
                    syncDate: syncDate,
                    glucose: newGlucose
                )
            } catch {
                debug(.deviceManager, "Failed to store glucose from CGM manager: \(error)")
            }
            glucoseStoreAndHeartLock.signal()
        }
    }

    var glucoseSource: GlucoseSource?

    func removeCalibrations() {
        calibrationService.removeAllCalibrations()
    }

    @MainActor func deleteGlucoseSource() async {
        cgmManager = nil
        glucoseSource = nil
        settingsManager.settings.cgm = cgmDefaultModel.type
        settingsManager.settings.cgmPluginIdentifier = cgmDefaultModel.id
        updateGlucoseSource(
            cgmGlucoseSourceType: cgmDefaultModel.type,
            cgmGlucosePluginId: cgmDefaultModel.id
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

        if let manager = newManager {
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

    func fetchGlucose() async throws -> [GlucoseStored]? {
        try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgoInMinutes,
            key: "date",
            ascending: false,
            fetchLimit: 350
        ) as? [GlucoseStored]
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

        let backfillGlucose = newGlucose.filter { $0.dateString <= syncDate }
        if backfillGlucose.isNotEmpty {
            debug(.deviceManager, "Backfilling glucose...")
            do {
                try await glucoseStorage.backfillGlucose(backfillGlucose)
            } catch {
                debug(.deviceManager, "Unable to backfill glucose: \(error)")
            }
        }

        filteredByDate = newGlucose.filter { $0.dateString > syncDate }
        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

        guard filtered.isNotEmpty else {
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
            return
        }
        debug(.deviceManager, "New glucose found")

        try await glucoseStorage.storeGlucose(filtered)

        if settingsManager.settings.smoothGlucose {
            await exponentialSmoothingGlucose(context: context)
        }

        deviceDataManager.heartbeat(date: Date())

        endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
    }

    func sourceInfo() -> [String: Any]? {
        glucoseSource?.sourceInfo()
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

extension BaseFetchGlucoseManager: SettingsObserver {
    /// Smooth glucose data when smoothing is turned on
    func settingsDidChange(_: TrioSettings) {
        if settingsManager.settings.smoothGlucose, !shouldSmoothGlucose {
            glucoseStoreAndHeartLock.wait()
            Task {
                await self.exponentialSmoothingGlucose(context: context)
                glucoseStoreAndHeartLock.signal()
            }
        }
        shouldSmoothGlucose = settingsManager.settings.smoothGlucose
    }
}

extension BaseFetchGlucoseManager {
    /// CoreData-friendly AAPS exponential smoothing + storage.
    /// - Important: Only stores `smoothedGlucose`. UI/alerts should still use `glucose`.
    func exponentialSmoothingGlucose(context: NSManagedObjectContext) async {
        let startTime = Date()

        guard let glucoseStored = try? await fetchGlucose() else { return }

        await context.perform {
            // Only smooth CGM values; ignore manually entered glucose
            // Keep only entries with dates
            let cgmValuesNewestFirst: [GlucoseStored] = glucoseStored
                .filter { !$0.isManual }
                .compactMap { obj -> GlucoseStored? in
                    guard obj.date != nil else { return nil }
                    return obj
                }
                .sorted { $0.date! > $1.date! } // newest first (AAPS expectation)

            guard !cgmValuesNewestFirst.isEmpty else { return }

            // Build a smoothing window size per AAPS rules (gap/xDrip error), then compute smoothed values for
            // the most recent `limit` entries. Older values are left unchanged (same as the Kotlin behavior).
            self.applyExponentialSmoothingAndStore(
                newestFirst: cgmValuesNewestFirst,
                minimumWindowSize: 4,
                maximumAllowedGapMinutes: 12,
                xDripErrorGlucose: 38,
                minimumSmoothedGlucose: 39,
                firstOrderWeight: 0.4,
                firstOrderAlpha: 0.5,
                secondOrderAlpha: 0.4,
                secondOrderBeta: 1.0
            )

            do {
                try context.save()
            } catch {
                // Replace with your logging system if you have one
                debugPrint("Failed to save context after smoothing: \(error)")
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        debugPrint(String(format: "Exponential smoothing duration: %0.04fs", duration))
    }

    private func applyExponentialSmoothingAndStore(
        newestFirst data: [GlucoseStored],
        minimumWindowSize: Int,
        maximumAllowedGapMinutes: Int,
        xDripErrorGlucose: Int,
        minimumSmoothedGlucose: Decimal,
        firstOrderWeight: Decimal,
        firstOrderAlpha: Decimal,
        secondOrderAlpha: Decimal,
        secondOrderBeta: Decimal
    ) {
        let recordCount = data.count
        guard recordCount > 0 else { return }

        // We need i+1 access while scanning gaps -> initial validWindowCount must be <= count-1
        var validWindowCount = max(recordCount - 1, 0)

        // Trim window based on rounded minute gaps or xDrip error value (38)
        if validWindowCount > 0 {
            for i in 0 ..< validWindowCount {
                guard let newerDate = data[i].date, let olderDate = data[i + 1].date else { continue }

                let gapSeconds = newerDate.timeIntervalSince(olderDate)
                let gapMinutesRounded = Int((gapSeconds / 60.0).rounded()) // Kotlin: round(...)

                if gapMinutesRounded >= maximumAllowedGapMinutes {
                    validWindowCount = i + 1 // include the more recent reading
                    break
                }

                if Int(data[i].glucose) == xDripErrorGlucose {
                    validWindowCount = i // exclude this 38 value
                    break
                }
            }
        }

        // If insufficient valid readings: copy raw into smoothed (clamped) for all passed entries
        guard validWindowCount >= minimumWindowSize else {
            for obj in data {
                let raw = Decimal(Int(obj.glucose))
                obj.smoothedGlucose = max(raw, minimumSmoothedGlucose) as NSDecimalNumber
                obj.direction = .none
            }
            return
        }

        // ---- 1st order smoothing (newest-first arrays, Kotlin add(0, ...) equivalent) ----
        var firstOrderSmoothed: [Decimal] = []
        firstOrderSmoothed.reserveCapacity(validWindowCount + 1)

        // Initialize with the oldest valid point (index validWindowCount - 1)
        firstOrderSmoothed = [Decimal(Int(data[validWindowCount - 1].glucose))]

        for i in 0 ..< validWindowCount {
            let raw = Decimal(Int(data[validWindowCount - 1 - i].glucose))
            let prev = firstOrderSmoothed[0]
            let next = prev + firstOrderAlpha * (raw - prev)
            firstOrderSmoothed.insert(next, at: 0)
        }

        // ---- 2nd order smoothing ----
        var secondOrderSmoothed: [Decimal] = []
        var secondOrderDelta: [Decimal] = []
        secondOrderSmoothed.reserveCapacity(validWindowCount)
        secondOrderDelta.reserveCapacity(validWindowCount)

        secondOrderSmoothed = [Decimal(Int(data[validWindowCount - 1].glucose))]
        secondOrderDelta = [
            Decimal(Int(data[validWindowCount - 2].glucose) - Int(data[validWindowCount - 1].glucose))
        ]

        for i in 0 ..< (validWindowCount - 1) {
            let raw = Decimal(Int(data[validWindowCount - 2 - i].glucose))

            let sBG = secondOrderSmoothed[0]
            let sD = secondOrderDelta[0]

            let nextBG = secondOrderAlpha * raw + (1 - secondOrderAlpha) * (sBG + sD)
            secondOrderSmoothed.insert(nextBG, at: 0)

            let nextD =
                secondOrderBeta * (secondOrderSmoothed[0] - secondOrderSmoothed[1])
                    + (1 - secondOrderBeta) * secondOrderDelta[0]
            secondOrderDelta.insert(nextD, at: 0)
        }

        // ---- Weighted blend ----
        var blended: [Decimal] = []
        blended.reserveCapacity(secondOrderSmoothed.count)

        for i in secondOrderSmoothed.indices {
            let value =
                firstOrderWeight * firstOrderSmoothed[i]
                    + (1 - firstOrderWeight) * secondOrderSmoothed[i]
            blended.append(value)
        }

        // Apply to the most recent `limit` readings (same behavior as Kotlin)
        let limit = min(blended.count, data.count)
        for i in 0 ..< limit {
            let rounded = blended[i].rounded(toPlaces: 0) // nearest integer, ties away from zero
            let clamped = max(rounded, minimumSmoothedGlucose)

            data[i].smoothedGlucose = clamped as NSDecimalNumber
            data[i].direction = .none
        }
    }
}
