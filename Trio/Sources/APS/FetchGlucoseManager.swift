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

    func fetchGlucose(context: NSManagedObjectContext) async throws -> [NSManagedObjectID] {
        // Compound predicate: time window + non-manual + valid date
        let timePredicate = NSPredicate.predicateForOneDayAgoInMinutes
        let manualPredicate = NSPredicate(format: "isManual == NO")
        let datePredicate = NSPredicate(format: "date != nil")

        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timePredicate,
            manualPredicate,
            datePredicate
        ])

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            // Predicate must cover at least the full glucose horizon used by downstream algorithm consumers.
            // If autosens / oref / smoothing logic ever starts looking back further (e.g. 36h),
            // this fetch window must be expanded accordingly.
            predicate: compoundPredicate,
            key: "date",
            ascending: true, // the first element is the oldest
            fetchLimit: 350
        )

        guard let glucoseArray = results as? [GlucoseStored] else {
            throw CoreDataError.fetchError(function: #function, file: #file)
        }

        return glucoseArray.map(\.objectID)
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
    /// Smooth glucose data when smoothing is turned on.
    func settingsDidChange(_: TrioSettings) {
        let smoothingWasEnabled = shouldSmoothGlucose
        let smoothingIsEnabled = settingsManager.settings.smoothGlucose
        shouldSmoothGlucose = smoothingIsEnabled

        guard smoothingIsEnabled, !smoothingWasEnabled else { return }

        processQueue.async { [weak self] in
            guard let self else { return }

            self.glucoseStoreAndHeartLock.wait()
            Task {
                await self.exponentialSmoothingGlucose(context: self.context)
                self.glucoseStoreAndHeartLock.signal()
            }
        }
    }
}

extension BaseFetchGlucoseManager {
    /// CoreData-friendly AAPS exponential smoothing + storage.
    /// - Important: Only stores `smoothedGlucose`. UI/alerts should still use `glucose`.
    ///
    func exponentialSmoothingGlucose(context: NSManagedObjectContext) async {
        let startTime = Date()

        do {
            // get objectIDs
            let objectIDs = try await fetchGlucose(context: context)

            try await context.perform {
                // Load managed objects from object IDs
                // Filtering (isManual, date) already done at DB level in fetchGlucose
                let glucoseReadings = objectIDs.compactMap {
                    context.object(with: $0) as? GlucoseStored
                }

                guard !glucoseReadings.isEmpty else { return }

                // Static method call to avoid self-capture
                Self.applyExponentialSmoothingAndStore(
                    glucoseReadings: glucoseReadings,
                    minimumWindowSize: 4,
                    maximumAllowedGapMinutes: 12,
                    xDripErrorGlucose: 38,
                    minimumSmoothedGlucose: 39,
                    firstOrderWeight: 0.4,
                    firstOrderAlpha: 0.5,
                    secondOrderAlpha: 0.4,
                    secondOrderBeta: 1.0
                )

                try context.save()
            }

            let duration = Date().timeIntervalSince(startTime)
            debugPrint(String(format: "Exponential smoothing duration: %0.04fs", duration))
        } catch {
            debug(.deviceManager, "Failed to smooth glucose: \(error)")
        }
    }

    private static func applyExponentialSmoothingAndStore(
        glucoseReadings data: [GlucoseStored],
        minimumWindowSize: Int,
        maximumAllowedGapMinutes: Int,
        xDripErrorGlucose: Int,
        minimumSmoothedGlucose: Decimal,
        firstOrderWeight: Decimal,
        firstOrderAlpha: Decimal,
        secondOrderAlpha: Decimal,
        secondOrderBeta: Decimal
    ) {
        guard !data.isEmpty else { return }

        // Determine the size of the valid most-recent smoothing window.
        // We walk adjacent pairs from newest -> oldest to preserve the same window semantics
        // as the original implementation, but avoid manual reverse indexing.
        var validWindowCount = max(data.count - 1, 0)

        for (recentOffset, pair) in zip(data.dropFirst().reversed(), data.dropLast().reversed()).enumerated() {
            let (newer, older) = pair

            guard let newerDate = newer.date, let olderDate = older.date else { continue }

            let gapSeconds = newerDate.timeIntervalSince(olderDate)
            let gapMinutesRounded = Int((gapSeconds / 60.0).rounded())

            if gapMinutesRounded >= maximumAllowedGapMinutes {
                validWindowCount = recentOffset + 1 // include the more recent reading
                break
            }

            // Ported from AAPS: 38 mg/dL may represent an xDrip error state.
            if Int(newer.glucose) == xDripErrorGlucose {
                validWindowCount = recentOffset // exclude this 38 value
                break
            }
        }

        // If insufficient valid readings: copy raw into smoothed (clamped) for all passed entries.
        guard validWindowCount >= minimumWindowSize else {
            for object in data {
                let raw = Decimal(Int(object.glucose))
                object.smoothedGlucose = max(raw, minimumSmoothedGlucose) as NSDecimalNumber
            }
            return
        }

        // Restrict smoothing to the valid most-recent window, still in chronological order.
        let validWindow = data.suffix(validWindowCount)

        guard let oldest = validWindow.first else { return }

        // ---- 1st order smoothing ----
        var firstOrderSmoothed: [Decimal] = []
        firstOrderSmoothed.reserveCapacity(validWindow.count)

        var firstOrderCurrent = Decimal(Int(oldest.glucose))
        firstOrderSmoothed.append(firstOrderCurrent)

        for sample in validWindow.dropFirst() {
            let raw = Decimal(Int(sample.glucose))
            firstOrderCurrent = firstOrderCurrent + firstOrderAlpha * (raw - firstOrderCurrent)
            firstOrderSmoothed.append(firstOrderCurrent)
        }

        // ---- 2nd order smoothing ----
        let secondOrderInput = Array(validWindow)
        guard secondOrderInput.count >= 2 else { return }

        var secondOrderSmoothed: [Decimal] = []
        secondOrderSmoothed.reserveCapacity(secondOrderInput.count)

        var secondOrderDeltas: [Decimal] = []
        secondOrderDeltas.reserveCapacity(secondOrderInput.count)

        var previousSecondOrderSmoothed = Decimal(Int(secondOrderInput[0].glucose))
        var previousSecondOrderDelta =
            Decimal(Int(secondOrderInput[1].glucose) - Int(secondOrderInput[0].glucose))

        secondOrderSmoothed.append(previousSecondOrderSmoothed)
        secondOrderDeltas.append(previousSecondOrderDelta)

        for sample in secondOrderInput.dropFirst() {
            let raw = Decimal(Int(sample.glucose))

            let nextSmoothed =
                secondOrderAlpha * raw
                    + (1 - secondOrderAlpha) * (previousSecondOrderSmoothed + previousSecondOrderDelta)

            let nextDelta =
                secondOrderBeta * (nextSmoothed - previousSecondOrderSmoothed)
                    + (1 - secondOrderBeta) * previousSecondOrderDelta

            previousSecondOrderSmoothed = nextSmoothed
            previousSecondOrderDelta = nextDelta

            secondOrderSmoothed.append(nextSmoothed)
            secondOrderDeltas.append(nextDelta)
        }

        // ---- Weighted blend ----
        let blended = zip(firstOrderSmoothed, secondOrderSmoothed).map { firstOrder, secondOrder in
            firstOrderWeight * firstOrder + (1 - firstOrderWeight) * secondOrder
        }

        // Apply to the most recent valid-window readings.
        for (object, blendedValue) in zip(validWindow, blended) {
            let rounded = blendedValue.rounded(toPlaces: 0) // nearest integer, ties away from zero
            let clamped = max(rounded, minimumSmoothedGlucose)
            object.smoothedGlucose = clamped as NSDecimalNumber
        }
    }
}
