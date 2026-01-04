import Combine
import ConnectIQ
import CoreData
import Foundation
import os
import Swinject

// Data transmission logic:
// - Datafield apps always receive data (bypass status checks as ConnectIQ status can be unreliable)
// - Watchface apps only receive data when watchface data transmission is enabled
// - Skip sending only if no apps are configured at all, or only watchface is configured with data disabled

// MARK: - GarminManager Protocol

/// Manages Garmin devices, allowing the app to select devices, update a known device list,
/// and send watch-state data to connected Garmin watch apps.
protocol GarminManager {
    /// Prompts the user to select Garmin devices, returning the chosen devices in a publisher.
    /// - Returns: A publisher that eventually outputs an array of selected `IQDevice` objects.
    func selectDevices() -> AnyPublisher<[IQDevice], Never>

    /// Updates the currently tracked device list. This typically persists the device list and
    /// triggers re-registration for any relevant ConnectIQ events.
    /// - Parameter devices: The new array of `IQDevice` objects to track.
    func updateDeviceList(_ devices: [IQDevice])

    /// Takes raw JSON-encoded watch-state data and dispatches it to any connected watch apps.
    /// - Parameter data: The JSON-encoded data representing the watch state.
    func sendWatchStateData(_ data: Data)

    /// The devices currently known to the app. May be loaded from disk or user selection.
    var devices: [IQDevice] { get }
}

// MARK: - BaseGarminManager

/// Concrete implementation of `GarminManager` that handles:
///  - Device registration/unregistration with Garmin ConnectIQ
///  - Data persistence for selected devices
///  - Generating & sending watch-state updates (glucose, IOB, COB, etc.) to Garmin watch apps.
final class BaseGarminManager: NSObject, GarminManager, Injectable, @unchecked Sendable {
    // MARK: - Dependencies & Properties

    /// Observes system-wide notifications, including `.openFromGarminConnect`.
    @Injected() private var notificationCenter: NotificationCenter!

    /// Broadcaster used for publishing or subscribing to global events (e.g., unit changes).
    @Injected() private var broadcaster: Broadcaster!

    /// APSManager containing insulin pump logic, e.g., for making bolus requests, reading basal info, etc.
    @Injected() private var apsManager: APSManager!

    /// Manages local user settings, such as glucose units (mg/dL or mmol/L).
    @Injected() private var settingsManager: SettingsManager!

    /// Stores, retrieves, and updates glucose data in CoreData.
    @Injected() private var glucoseStorage: GlucoseStorage!

    /// Stores, retrieves, and updates insulin dose determinations in CoreData.
    @Injected() private var determinationStorage: DeterminationStorage!

    @Injected() private var iobService: IOBService!

    /// Persists the user's device list between app launches.
    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    /// Router for presenting alerts or navigation flows (injected via Swinject).
    private let router: Router

    /// Garmin ConnectIQ shared instance for watch interactions.
    private let connectIQ = ConnectIQ.sharedInstance()

    /// Keeps references to watch apps (both watchface & data field) for each registered device.
    private var watchApps: [IQApp] = []

    /// A set of Combine cancellables for managing the lifecycle of various subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Holds a promise used when the user is selecting devices (via `showDeviceSelection()`).
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

    /// Enable/disable debug logging for watch state (SwissAlpine/Trio data being sent)
    private let debugWatchState = true // Set to false to disable debug logging

    /// Enable/disable general Garmin debug logging (connections, settings, throttling, etc.)
    private let debugGarmin = true // Set to false to disable verbose Garmin logging

    /// Enable simulated Garmin device for Xcode Simulator testing
    /// When true, creates a fake Garmin device so you can test the workflow in Simulator
    #if targetEnvironment(simulator)
        private let enableSimulatedDevice = true // Set to false to disable simulated device
    #else
        private let enableSimulatedDevice = false // Never enable on real device
    #endif

    /// Helper method for conditional Garmin debug logging
    private func debugGarmin(_ message: String) {
        guard debugGarmin else { return }
        debug(.watchManager, message)
    }

    /// Track when immediate sends happen to cancel throttled ones
    private var lastImmediateSendTime: Date?
    private var throttledUpdatePending = false

    /// Track last sent data hash to prevent duplicate sends
    private var lastSentDataHash: Int?
    private let lastSentHashLock = NSLock()

    /// Cache last determination data to avoid CoreData staleness on immediate sends
    private var cachedDeterminationData: Data?

    /// Track when watchface was last changed to prevent caching stale format data
    private var lastWatchfaceChangeTime: Date?

    /// Cache of app installation status to avoid expensive checks before data preparation
    /// Key: app UUID string, Value: (status, lastChecked)
    /// Using enum to distinguish between "not installed" vs "unknown due to connection issue"
    private var appInstallationCache: [String: (status: AppCacheStatus, lastChecked: Date)] = [:]
    private let appStatusCacheLock = NSLock()

    /// How long to trust cached app status (in seconds)
    private let appStatusCacheTimeout: TimeInterval = 60 // 1 minute

    /// Track device connection states to make intelligent caching decisions
    private var deviceConnectionStates: [UUID: IQDeviceStatus] = [:]

    /// App installation cache status enum
    private enum AppCacheStatus {
        case installed
        case notInstalled
        case unknown // Can't determine due to connection issues

        var shouldSendData: Bool {
            switch self {
            case .installed: return true
            case .notInstalled: return false
            case .unknown: return true // Optimistic when uncertain
            }
        }
    }

    /// Throttle duration for non-critical updates (settings changes)
    private let throttleDuration: TimeInterval = 10

    /// Deduplication: Track last prepared data hash to prevent duplicate expensive work
    private var lastPreparedDataHash: Int?
    private var lastPreparedWatchState: [GarminWatchState]?
    private let hashLock = NSLock()

    /// Array of Garmin `IQDevice` objects currently tracked.
    /// Changing this property triggers re-registration and updates persisted devices.
    private(set) var devices: [IQDevice] = [] {
        didSet {
            // Persist newly updated device list
            persistedDevices = devices.map(GarminDevice.init)
            // Re-register for events, app messages, etc.
            registerDevices(devices)
        }
    }

    /// Current glucose units, either mg/dL or mmol/L, read from user settings.
    private var units: GlucoseUnits = .mgdL
    /// Track previous Garmin settings as a single struct
    private var previousGarminSettings = GarminWatchSettings()

    /// Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseGarminManager.queue", qos: .utility)

    /// Dedicated queue for throttle timers to avoid blocking main thread
    private let timerQueue = DispatchQueue(label: "BaseGarminManager.timerQueue", qos: .utility)

    /// Publishes any changed CoreData objects that match our filters (e.g., OrefDetermination, GlucoseStored).
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?

    /// Additional local subscriptions (separate from `cancellables`) for CoreData events.
    private var subscriptions = Set<AnyCancellable>()

    /// Represents the context for background tasks in CoreData.
    let backgroundContext = CoreDataStack.shared.newTaskContext()

    /// Represents the main (view) context for CoreData, typically used on the main thread.
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    // MARK: - Initialization

    /// Creates a new `BaseGarminManager`, injecting required services, restoring any persisted devices,
    /// and setting up watchers for data changes (e.g., glucose updates).
    /// - Parameter resolver: Swinject resolver for injecting dependencies like the Router.
    init(resolver: Resolver) {
        router = resolver.resolve(Router.self)!
        super.init()
        injectServices(resolver)

        connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)

        restoreDevices()

        // Add simulated device for Xcode Simulator testing
        #if targetEnvironment(simulator)
            if enableSimulatedDevice, devices.isEmpty {
                addSimulatedGarminDevice()
            }
        #endif

        subscribeToOpenFromGarminConnect()
        subscribeToDeterminationThrottle()

        units = settingsManager.settings.units

        previousGarminSettings = settingsManager.settings.garminSettings

        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        // Glucose updates - only send immediately if loop is stale (> 8 minutes)
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }

                // Skip if no Garmin devices are connected (unless in simulator)
                #if targetEnvironment(simulator)
                // Allow processing in simulator even without devices
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                Task {
                    do {
                        // Check loop age
                        let determinationIds = try await self.determinationStorage.fetchLastDeterminationObjectID(
                            predicate: NSPredicate.enactedDetermination
                        )

                        let loopAge = await self.getLoopAge(determinationIds)

                        // Send if loop is stale (> 8 minutes) OR no recent loop data available (>30 min)
                        if loopAge > 480 || loopAge.isInfinite {
                            // Skip expensive data preparation if no apps are installed (based on cache)
                            guard self.areAppsLikelyInstalled() else {
                                return
                            }

                            let watchState = try await self.setupGarminWatchState(triggeredBy: "Glucose-Stale-Loop")
                            let watchStateData = try JSONEncoder().encode(watchState)

                            if loopAge.isInfinite {
                                self.currentSendTrigger = "Glucose-Stale-Loop (no loop data)"
                                debug(
                                    .watchManager,
                                    "[\\(self.formatTimeForLog())] Garmin: Glucose sent immediately - no loop data available (>30m)"
                                )
                            } else {
                                let loopAgeMinutes = Int(loopAge / 60)
                                self.currentSendTrigger = "Glucose-Stale-Loop (\\(loopAgeMinutes)m)"
                                debug(
                                    .watchManager,
                                    "[\\(self.formatTimeForLog())] Garmin: Glucose sent immediately - loop age > 8 min (\\(loopAgeMinutes)m)"
                                )
                            }

                            self.sendWatchStateDataImmediately(watchStateData)
                            self.lastImmediateSendTime = Date()
                        }
                        // If loop age < 8 min, skip silently - determination trigger will handle it
                    } catch {
                        debug(
                            .watchManager,
                            "\\(DebuggingIdentifiers.failed) Error checking loop age: \\(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)

        // IOB trigger - can be reactivated if needed
        // Commented out to prevent duplicate updates since IOB changes are captured by determinations
        /*
         iobService.iobPublisher
             .receive(on: DispatchQueue.global(qos: .background))
             .sink { [weak self] _ in
                 guard let self = self else { return }

                 // Skip if no Garmin devices are connected (unless in simulator)
                 #if targetEnvironment(simulator)
                 // Allow processing in simulator even without devices
                 #else
                     guard !self.devices.isEmpty else { return }
                 #endif

                 Task {
                     do {
                         let watchState = try await self.setupGarminWatchState(triggeredBy: "IOB-Update")
                         let watchStateData = try JSONEncoder().encode(watchState)
                         self.currentSendTrigger = "IOB-Update"
                         // Use same throttled pipeline as determinations
                         self.determinationSubject.send(watchStateData)
                     } catch {
                         debug(
                             .watchManager,
                             "\(DebuggingIdentifiers.failed) Error updating watch state: \(error)"
                         )
                     }
                 }
             }
             .store(in: &subscriptions)
         */

        registerHandlers()
    }

    // MARK: - Helper Properties

    /// Safely gets the current Garmin watchface setting
    private var currentWatchface: GarminWatchface {
        // Direct access since it's not optional
        settingsManager.settings.garminSettings.watchface
    }

    /// Check if current watchface needs historical glucose data (23 additional readings)
    /// Only SwissAlpine watchface uses historical data, Trio only needs current reading
    private var needsHistoricalGlucoseData: Bool {
        // SwissAlpine watchface uses elements 1-23 for historical graph
        // Trio watchface only uses element 0 (current reading)
        currentWatchface == .swissalpine
    }

    /// Gets the current Garmin settings struct
    private var currentGarminSettings: GarminWatchSettings {
        settingsManager.settings.garminSettings
    }

    /// Check if watchface data transmission is enabled
    private var isWatchfaceDataEnabled: Bool {
        settingsManager.settings.garminSettings.isWatchfaceDataEnabled
    }

    // MARK: - Internal Setup / Handlers

    /// Sets up handlers for OrefDetermination and GlucoseStored entity changes in CoreData.
    /// When these change, we re-compute the Garmin watch state and send updates to the watch.
    private func registerHandlers() {
        // OrefDetermination - debounce at CoreData level to avoid redundant data preparation
        // Multiple determination saves happen within 1-2 seconds during a loop run
        // Debouncing here prevents fetching glucose/basals/IOB multiple times for the same loop
        coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main) // Wait 2s after last save before expensive work
            .sink { [weak self] _ in
                guard let self = self else { return }

                // Skip if no Garmin devices are connected (unless in simulator)
                #if targetEnvironment(simulator)
                // Allow processing in simulator even without devices
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                // Skip expensive data preparation if no apps are installed (based on cache)
                guard self.areAppsLikelyInstalled() else {
                    return
                }

                Task {
                    do {
                        let watchState = try await self.setupGarminWatchState(triggeredBy: "Determination")

                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.currentSendTrigger = "Determination"

                        // Send to subject for 2s debouncing before Bluetooth transmission
                        // Hash-based caching in setupGarminWatchState prevents unnecessary work
                        // No additional blocking needed - debounce handles deduplication
                        self.determinationSubject.send(watchStateData)
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Failed to update watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)

        // Note: Glucose deletion handler removed - new glucose entries were incorrectly
        // triggering this handler, causing duplicate sends before determination updates.
        // Deletions are rare and will be handled by the next regular update cycle.
    }

    /// Helper to get loop age in seconds
    private func getLoopAge(_ determinationIds: [NSManagedObjectID]) async -> TimeInterval {
        guard !determinationIds.isEmpty else { return .infinity }

        do {
            let determinations: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)

            return await backgroundContext.perform {
                guard let latest = determinations.first,
                      let timestamp = latest.timestamp
                else {
                    return TimeInterval.infinity
                }

                return Date().timeIntervalSince(timestamp)
            }
        } catch {
            return .infinity
        }
    }

    /// Throttle for Status/Settings updates
    private func sendWatchStateDataWithThrottle(_ data: Data) {
        // Store the latest data (always keep the newest)
        pendingThrottledData = data

        // If work item is already scheduled, just update data - DON'T reschedule
        if throttleWorkItem != nil {
            debug(
                .watchManager,
                "[\(formatTimeForLog())] Garmin: throttle timer running, data updated [Trigger: \(currentSendTrigger)]"
            )
            return
        }

        // Create and schedule new work item on dedicated timer queue
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self,
                  let dataToSend = self.pendingThrottledData
            else {
                return
            }

            // Check if immediate send happened while we were waiting
            // Use throttle duration window to prevent duplicates
            if let lastImmediate = self.lastImmediateSendTime,
               Date().timeIntervalSince(lastImmediate) < self.throttleDuration
            {
                debugGarmin("[\(self.formatTimeForLog())] Garmin: timer cancelled - recent immediate send")
                self.throttleWorkItem = nil
                self.pendingThrottledData = nil
                self.throttledUpdatePending = false
                return
            }

            // Convert data to JSON object for sending
            guard let jsonObject = try? JSONSerialization.jsonObject(with: dataToSend, options: []) else {
                debugGarmin("[\(self.formatTimeForLog())] Garmin: Invalid JSON in throttled data")
                self.throttleWorkItem = nil
                self.pendingThrottledData = nil
                self.throttledUpdatePending = false
                return
            }

            debugGarmin("[\(self.formatTimeForLog())] Garmin: timer fired - sending collected updates")
            self.broadcastStateToWatchApps(jsonObject as Any)

            // Clean up
            self.throttleWorkItem = nil
            self.pendingThrottledData = nil
            self.throttledUpdatePending = false
        }

        throttleWorkItem = workItem
        timerQueue.asyncAfter(deadline: .now() + throttleDuration, execute: workItem)
        throttledUpdatePending = true
        debugGarmin("[\(formatTimeForLog())] Garmin: throttle timer started (\(Int(throttleDuration))s) on dedicated queue")
    }

    /// Fetches recent glucose readings from CoreData, up to specified limit.
    /// - Returns: An array of `NSManagedObjectID`s for glucose readings.
    private func fetchGlucose(limit: Int = 5) async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: limit
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Fetches recent temp basal events from CoreData pump history.
    /// - Returns: An array of `NSManagedObjectID`s for pump events with temp basals.
    private func fetchTempBasals() async throws -> [NSManagedObjectID] {
        let tempBasalPredicate = NSPredicate(format: "tempBasal != nil")
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.pumpHistoryLast24h,
            tempBasalPredicate
        ])

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: compoundPredicate,
            key: "timestamp",
            ascending: false, // Most recent first
            fetchLimit: 1
        )

        return try await backgroundContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return pumpEvents.map(\.objectID)
        }
    }

    // MARK: - Watch State Setup

    /// Computes a hash of key data points to detect if watch state preparation would produce identical results.
    /// This prevents expensive CoreData fetches and calculations when data hasn't actually changed.
    /// - Returns: Hash value representing current state of glucose, IOB, COB, and basal data
    private func computeDataHash() async -> Int {
        var hasher = Hasher()

        do {
            // Hash latest glucose reading (most critical data point)
            let glucoseIds = try await fetchGlucose(limit: 1)
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)

            if let latestGlucose = glucoseObjects.first {
                await backgroundContext.perform {
                    hasher.combine(latestGlucose.glucose)
                    hasher.combine(latestGlucose.date?.timeIntervalSince1970 ?? 0)
                    hasher.combine(latestGlucose.direction ?? "")
                }
            }

            // Hash IOB (changes frequently with insulin activity)
            if let iob = iobService.currentIOB {
                let iobValue = validateIOB(iob)
                hasher.combine(iobValue)
            }

            // Hash latest determination data (includes COB, ISF, eventualBG, sensRatio)
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.enactedDetermination
            )
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)

            if let determination = determinationObjects.first {
                await backgroundContext.perform {
                    // Hash COB (rounded to integer)
                    let cobValue = self.validateCOB(determination.cob)
                    hasher.combine(Int16(cobValue))

                    // Hash sensRatio with 2 decimal precision
                    let sensValue = self.validateSensRatio(determination.sensitivityRatio)
                    hasher.combine(sensValue)

                    // Hash ISF (insulinSensitivity)
                    if let isf = self.validateISF(determination.insulinSensitivity) {
                        hasher.combine(isf)
                    }

                    // Hash eventualBG
                    if let eventualBG = self.validateEventualBG(determination.eventualBG) {
                        hasher.combine(eventualBG)
                    }
                }
            }

            // Hash current basal rate (from temp basal or profile)
            let tempBasalIds = try await fetchTempBasals()
            let tempBasalObjects: [PumpEventStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: tempBasalIds, context: backgroundContext)

            if let latestTempBasal = tempBasalObjects.first {
                await backgroundContext.perform {
                    if let tempBasalData = latestTempBasal.tempBasal,
                       let rate = tempBasalData.rate
                    {
                        let rateDouble = Double(truncating: rate)
                        if rateDouble.isFinite, !rateDouble.isNaN {
                            let rateRounded = rateDouble.roundedDouble(toPlaces: 1)
                            hasher.combine(rateRounded)
                        }
                    }
                }
            }

        } catch {
            debugGarmin("[\(formatTimeForLog())] ⚠️ Error computing data hash: \(error)")
        }

        return hasher.finalize()
    }

    /// Builds a GarminWatchState array for both Trio and SwissAlpine watchfaces.
    /// Uses the SwissAlpine numeric format for all data, sent as an array.
    /// Both watchfaces receive the same data structure with display configuration fields.
    /// - Parameter triggeredBy: Source of the trigger (for logging/debugging purposes)
    /// - Returns: Array of GarminWatchState objects ready to be sent to watch
    func setupGarminWatchState(triggeredBy: String = #function) async throws -> [GarminWatchState] {
        // Skip expensive calculations if no Garmin devices are connected (except in simulator)
        #if targetEnvironment(simulator)
            let skipDeviceCheck = true
        #else
            let skipDeviceCheck = false
        #endif

        guard !devices.isEmpty || skipDeviceCheck else {
            debug(.watchManager, "⌚️⛔ Skipping setupGarminWatchState - No Garmin devices connected")
            return []
        }

        // Compute hash of current data to detect if preparation would produce identical results
        let currentHash = await computeDataHash()

        // Check if data is unchanged
        hashLock.lock()
        let hashMatches = (currentHash == lastPreparedDataHash)
        let hasCachedState = (lastPreparedWatchState != nil)
        hashLock.unlock()

        if hashMatches, hasCachedState {
            if debugWatchState {
                debugGarmin(
                    "[\(formatTimeForLog())] ⏭️ Skipping preparation - data unchanged (hash: \(currentHash)) [Triggered by: \(triggeredBy)]"
                )
            }
            return lastPreparedWatchState!
        }

        if debugWatchState {
            debugGarmin("[\(formatTimeForLog())] ⌚️ Preparing data (hash: \(currentHash)) [Triggered by: \(triggeredBy)]")
        }

        do {
            // Optimize glucose fetch based on watchface needs
            // SwissAlpine: Fetch 24 entries for historical graph (elements 0-23)
            // Trio: Fetch 2 entries minimum (to calculate delta), but only send 1 to watchface
            // We need at least 2 readings to calculate delta (current - previous)
            let glucoseLimit = needsHistoricalGlucoseData ? 24 : 2
            let glucoseIds = try await fetchGlucose(limit: glucoseLimit)

            if debugWatchState {
                debug(
                    .watchManager,
                    "⌚️ Fetching \(glucoseLimit) glucose reading(s) for \(currentWatchface.displayName) watchface (need 2+ for delta)"
                )
            }

            // Fetch the latest OrefDetermination object if available
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.enactedDetermination
            )

            // Fetch temp basal from pump history
            let tempBasalIds = try await fetchTempBasals()

            // Turn those IDs into live NSManagedObjects
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)
            let tempBasalObjects: [PumpEventStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: tempBasalIds, context: backgroundContext)

            // Perform logic on the background context
            return await backgroundContext.perform {
                var watchStates: [GarminWatchState] = []

                // Get units hint - always send "mgdl" since we're always transmitting mg/dL
                let unitsHint = self.units == .mgdL ? "mgdl" : "mmol"

                // Calculate IOB with 1 decimal precision using helper function
                let iobValue = self.validateIOB(self.iobService.currentIOB ?? Decimal(0))

                // Calculate COB, sensRatio, ISF, eventualBG, TBR from determination
                var cobValue: Double?
                var sensRatioValue: Double?
                var isfValue: Int16?
                var eventualBGValue: Int16?
                var tbrValue: Double?

                if let latestDetermination = determinationObjects.first {
                    // Safe COB conversion using helper
                    cobValue = self.validateCOB(latestDetermination.cob)
                    if cobValue == 0, self.debugWatchState {
                        debug(.watchManager, "⌚️ COB is invalid or 0")
                    }

                    // Calculate sensRatio using helper (returns 1.0 if invalid)
                    sensRatioValue = self.validateSensRatio(latestDetermination.sensitivityRatio)
                    if sensRatioValue == 1.0, latestDetermination.sensitivityRatio == nil, self.debugWatchState {
                        debug(.watchManager, "⌚️ SensRatio is nil, using default 1.0")
                    }

                    // ISF validation using helper - stored as Int16 in CoreData (mg/dL values)
                    isfValue = self.validateISF(latestDetermination.insulinSensitivity)
                    if isfValue == nil, self.debugWatchState {
                        debug(.watchManager, "⌚️ ISF out of range or invalid, excluding from data")
                    }

                    // EventualBG validation using helper
                    eventualBGValue = self.validateEventualBG(latestDetermination.eventualBG)
                    if eventualBGValue == nil, self.debugWatchState {
                        debug(.watchManager, "⌚️ EventualBG out of range or invalid, excluding from data")
                    }
                }

                // Get current basal rate directly from temp basal
                if let firstTempBasal = tempBasalObjects.first, // Most recent temp basal
                   let tempBasalData = firstTempBasal.tempBasal,
                   let tempRate = tempBasalData.rate
                {
                    // Send raw value without rounding, with NaN/Infinity guard
                    let tbrDouble = Double(truncating: tempRate)
                    if tbrDouble.isFinite, !tbrDouble.isNaN {
                        tbrValue = tbrDouble
                        if self.debugWatchState {
                            debug(.watchManager, "⌚️ Current basal rate: \(tbrValue!) U/hr from temp basal")
                        }
                    } else {
                        tbrValue = nil
                        if self.debugWatchState {
                            debug(.watchManager, "⌚️ TBR is NaN or infinite, excluding from data")
                        }
                    }
                } else {
                    // If no temp basal, get scheduled basal from profile
                    let basalProfile = self.settingsManager.preferences.basalProfile as? [BasalProfileEntry] ?? []
                    if !basalProfile.isEmpty {
                        let now = Date()
                        let calendar = Calendar.current
                        let currentTimeMinutes = calendar.component(.hour, from: now) * 60 + calendar
                            .component(.minute, from: now)

                        // Find the current basal rate from profile
                        var currentBasalRate: Double = 0
                        for entry in basalProfile.reversed() {
                            if entry.minutes <= currentTimeMinutes {
                                let rateDouble = Double(entry.rate)
                                if rateDouble.isFinite, !rateDouble.isNaN {
                                    currentBasalRate = rateDouble
                                }
                                break
                            }
                        }

                        if currentBasalRate > 0 {
                            // Send raw value without rounding
                            tbrValue = currentBasalRate

                            if self.debugWatchState {
                                debug(.watchManager, "⌚️ Current scheduled basal rate: \(tbrValue!) U/hr from profile")
                            }
                        }
                    }
                }

                // Get display configuration from settings
                let displayPrimaryAttributeChoice = self.settingsManager.settings.garminSettings.primaryAttributeChoice.rawValue
                let displaySecondaryAttributeChoice = self.settingsManager.settings.garminSettings.secondaryAttributeChoice
                    .rawValue

                // Process glucose readings
                // For Trio: Process 2 readings (to calculate delta) but only send 1 entry
                // For SwissAlpine: Process and send all 24 entries

                // Calculate most recent timestamp once (outside loop)
                let mostRecentTimestamp: UInt64? = {
                    if let latestDetermination = determinationObjects.first,
                       let loopTimestamp = latestDetermination.timestamp
                    {
                        return UInt64(loopTimestamp.timeIntervalSince1970 * 1000)
                    }
                    return nil
                }()

                // Process glucose readings
                // All watchfaces expect array structure, but only SwissAlpine uses elements 1-23
                let entriesToSend = self.needsHistoricalGlucoseData ? glucoseObjects.count : 1

                for (index, glucose) in glucoseObjects.enumerated() {
                    guard index < entriesToSend else { break }

                    // Validate glucose value early
                    let glucoseValue = glucose.glucose
                    guard glucoseValue >= 0, glucoseValue <= 500 else {
                        if self.debugWatchState {
                            debug(.watchManager, "⌚️ Invalid glucose value (\(glucoseValue)), skipping")
                        }
                        continue
                    }

                    var watchState = GarminWatchState()

                    // Set timestamp
                    if index == 0 {
                        watchState.date = mostRecentTimestamp ?? glucose.date.map { UInt64($0.timeIntervalSince1970 * 1000) }
                    } else {
                        watchState.date = glucose.date.map { UInt64($0.timeIntervalSince1970 * 1000) }
                    }

                    watchState.sgv = glucoseValue

                    // Only add delta/direction for first entry
                    if index == 0 {
                        watchState.direction = glucose.direction ?? "--"

                        if glucoseObjects.count > 1 {
                            let deltaValue = glucose.glucose - glucoseObjects[1].glucose
                            watchState.delta = (deltaValue >= -100 && deltaValue <= 100) ? deltaValue : nil
                        } else {
                            watchState.delta = 0
                        }

                        // Add extended data
                        watchState.units_hint = unitsHint
                        watchState.iob = iobValue
                        watchState.cob = cobValue
                        watchState.tbr = tbrValue
                        watchState.isf = isfValue
                        watchState.eventualBG = eventualBGValue
                        watchState.sensRatio = sensRatioValue
                        watchState.displayPrimaryAttributeChoice = displayPrimaryAttributeChoice
                        watchState.displaySecondaryAttributeChoice = displaySecondaryAttributeChoice
                    }

                    watchStates.append(watchState)
                }

                // Log the watch states if debugging is enabled
                if self.debugWatchState {
                    self.logWatchState(watchStates)
                }

                // Cache the hash and prepared state for deduplication
                self.hashLock.lock()
                self.lastPreparedDataHash = currentHash
                self.lastPreparedWatchState = watchStates
                self.hashLock.unlock()

                return watchStates
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up unified Garmin watch state: \(error)"
            )
            throw error
        }
    }

    // MARK: - Debug Logging Method for Watch State

    private func logWatchState(_ watchState: [GarminWatchState]) {
        guard debugWatchState else { return }

        let watchface = currentWatchface
        let datafield = currentGarminSettings.datafield
        let watchfaceUUID = watchface.watchfaceUUID?.uuidString ?? "Unknown"
        let datafieldUUID = datafield.datafieldUUID?.uuidString ?? "Unknown"

        do {
            let jsonData = try JSONEncoder().encode(watchState)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let compactJson = jsonString.replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "  ", with: " ")

                // Show which apps will actually receive data
                let destinations: String
                if !isWatchfaceDataEnabled {
                    destinations = "datafield \(datafieldUUID) only (watchface disabled)"
                } else {
                    destinations = "watchface \(watchfaceUUID) / datafield \(datafieldUUID)"
                }

                debug(
                    .watchManager,
                    "📱 (\(watchface.displayName)): Prepared \(watchState.count) entries for \(destinations): \(compactJson)"
                )
            }
        } catch {
            debug(.watchManager, "📱 Prepared \(watchState.count) entries (failed to encode for logging)")
        }
    }

    // MARK: - Helper Methods

    /// Formats a Date to HH:mm:ss string for logging
    private func formatTimeForLog(_ date: Date = Date()) -> String {
        Formatter.timeForLogFormatter.string(from: date)
    }

    // MARK: - Simulated Device (for Xcode Simulator Testing)

    #if targetEnvironment(simulator)
        /// Creates a simulated Garmin device for testing in Xcode Simulator
        /// This allows testing the full workflow without a real Garmin watch
        private func addSimulatedGarminDevice() {
            guard enableSimulatedDevice else { return }

            // Create a mock IQDevice for simulator testing
            // Using a fixed UUID so it persists across app launches
            let simulatedUUID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

            // Note: IQDevice initializer may vary - adjust as needed
            // This is a placeholder that may need adjustment based on actual IQDevice API
            if let simulatedDevice = createMockIQDevice(
                uuid: simulatedUUID,
                friendlyName: "Simulated Garmin Watch",
                modelName: "Enduro 3 (Simulator)"
            ) {
                devices = [simulatedDevice]
                debugGarmin("📱 Simulator: Added simulated Garmin device for testing")
                debugGarmin("📱 Simulator: Device UUID: \(simulatedUUID)")
                debugGarmin("📱 Simulator: Use this to test determination/IOB throttling, settings changes, etc.")
            } else {
                debugGarmin("⚠️ Simulator: Could not create simulated device (IQDevice API may have changed)")
            }
        }

        /// Helper to create a mock IQDevice - implementation depends on IQDevice's actual initializers
        private func createMockIQDevice(uuid _: UUID, friendlyName _: String, modelName _: String) -> IQDevice? {
            // Note: This is a placeholder - the actual IQDevice creation may require
            // different parameters or may not be possible to mock directly.
            // You may need to adjust this based on ConnectIQ SDK documentation.

            // If IQDevice can't be created directly, you might need to:
            // 1. Use a real device connection once and persist it
            // 2. Or modify IQDevice to support test initialization
            // 3. Or create a protocol and use dependency injection

            // For now, returning nil as IQDevice likely requires Garmin SDK initialization
            // Users should connect a real device once, then it will be persisted
            nil
        }
    #endif

    // MARK: - Device & App Registration

    /// Registers the given devices for ConnectIQ events (device status changes) and watch app messages.
    /// It also creates and registers watch apps (watchface + data field) for each device.
    /// - Parameter devices: The devices to register.
    private func registerDevices(_ devices: [IQDevice]) {
        // Clear out old references
        watchApps.removeAll()

        // Clear app installation cache since we're re-registering
        appStatusCacheLock.lock()
        appInstallationCache.removeAll()
        appStatusCacheLock.unlock()
        debugGarmin("Garmin: Cleared app installation cache on device registration")

        for device in devices {
            // Listen for device-level status changes
            connectIQ?.register(forDeviceEvents: device, delegate: self)

            // Get current watchface setting
            let watchface = currentWatchface

            // Get current datafield setting
            let datafield = currentGarminSettings.datafield

            // Create a watchface app using the UUID from the enum
            // Only register watchface if data is enabled
            if isWatchfaceDataEnabled {
                if let watchfaceUUID = watchface.watchfaceUUID,
                   let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
                {
                    debug(
                        .watchManager,
                        "Garmin: Registering \(watchface.displayName) watchface (UUID: \(watchfaceUUID)) for device \(device.friendlyName ?? "Unknown")"
                    )

                    // Track watchface app
                    watchApps.append(watchfaceApp)

                    // Register to receive app-messages from the watchface
                    connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
                } else {
                    debug(
                        .watchManager,
                        "Garmin: Could not create \(watchface.displayName) watchface app for device \(device.uuid!)"
                    )
                }
            } else {
                debugGarmin("Garmin: Skipping watchface registration - data disabled")
            }

            // ALWAYS create and register data field app (not affected by disable setting)
            if let datafieldUUID = datafield.datafieldUUID,
               let watchDataFieldApp = IQApp(uuid: datafieldUUID, store: UUID(), device: device)
            {
                debug(
                    .watchManager,
                    "Garmin: Registering \(datafield.displayName) datafield (UUID: \(datafieldUUID)) for device \(device.friendlyName ?? "Unknown")"
                )

                // Track datafield app
                watchApps.append(watchDataFieldApp)

                // Register to receive app-messages from the datafield
                connectIQ?.register(forAppMessages: watchDataFieldApp, delegate: self)
            } else {
                debugGarmin("Garmin: Could not create datafield app for device \(device.uuid!)")
            }
        }
    }

    /// Restores previously persisted devices from local storage into `devices`.
    private func restoreDevices() {
        devices = persistedDevices.map(\.iqDevice)
    }

    // MARK: - Combine Subscriptions

    /// Subscribes to the `.openFromGarminConnect` notification, parsing devices from the given URL
    /// and updating the device list accordingly.
    private func subscribeToOpenFromGarminConnect() {
        notificationCenter
            .publisher(for: .openFromGarminConnect)
            .sink { [weak self] notification in
                guard
                    let self = self,
                    let url = notification.object as? URL
                else { return }

                self.parseDevices(for: url)
            }
            .store(in: &cancellables)
    }

    /// Subscribes to determination updates with 2s debounce (waits for quiet period, then sends latest)
    /// Also handles IOB updates since they fire simultaneously with determinations
    /// Two-stage debouncing: 2s at CoreData level (skip redundant prep) + 2s here (skip redundant sends)
    /// Total delay: ~4s from first CoreData save to Bluetooth transmission (faster than old 10s throttle)
    private func subscribeToDeterminationThrottle() {
        determinationSubject
            .debounce(for: .seconds(2), scheduler: timerQueue)
            .sink { [weak self] data in
                guard let self = self else { return }

                // Only cache if no recent watchface change (within last 6 seconds)
                // This prevents caching stale format data that was in the debounce pipeline
                let shouldCache: Bool
                if let lastChange = self.lastWatchfaceChangeTime {
                    let timeSinceChange = Date().timeIntervalSince(lastChange)
                    shouldCache = timeSinceChange > 6 // 2s CoreData + 2s send debounce + 2s buffer
                    if !shouldCache {
                        debugGarmin(
                            "[\(self.formatTimeForLog())] Garmin: Not caching - data may be from before watchface change (\(Int(timeSinceChange))s ago)"
                        )
                    }
                } else {
                    shouldCache = true // No recent watchface change
                }

                if shouldCache {
                    self.cachedDeterminationData = data
                }

                self.lastImmediateSendTime = Date() // Mark for any pending throttled timers (status requests, settings)

                // Cancel any pending throttled send since determination is sending immediately
                self.throttleWorkItem?.cancel()
                self.throttleWorkItem = nil
                self.pendingThrottledData = nil
                self.throttledUpdatePending = false

                // Convert data to JSON object for sending
                guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    debugGarmin("[\(self.formatTimeForLog())] Garmin: Invalid JSON in determination data")
                    return
                }

                debugGarmin("[\(self.formatTimeForLog())] Garmin: Sending determination/IOB (2s debounce passed)")
                self.broadcastStateToWatchApps(jsonObject as Any)
            }
            .store(in: &cancellables)
    }

    // MARK: - Parsing & Broadcasting

    /// Parses devices from a Garmin Connect URL and updates our `devices` property.
    /// - Parameter url: The URL provided by Garmin Connect containing device selection info.
    private func parseDevices(for url: URL) {
        let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice]
        devices = parsed ?? []

        // Fulfill any pending promise in case this is in response to `selectDevices()`.
        deviceSelectionPromise?(.success(devices))
        deviceSelectionPromise = nil
    }

    /// Broadcasts state to watch apps
    /// Always sends to datafield (if exists), only checks status for watchface
    /// - Parameter state: The dictionary representing the watch state to be broadcast.
    private func broadcastStateToWatchApps(_ state: Any) {
        // Deduplicate: Check if we're sending identical data by hashing the JSON content
        let currentHash: Int
        if let jsonData = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            currentHash = jsonData.hashValue
        } else {
            currentHash = 0 // Fallback if serialization fails
        }

        lastSentHashLock.lock()
        let isDuplicate = (lastSentDataHash == currentHash)
        lastSentHashLock.unlock()

        if isDuplicate {
            debugGarmin("[\(formatTimeForLog())] Garmin: Skipping duplicate broadcast (hash: \(currentHash))")
            return
        }

        // Store hash - will be marked as "sent" only after successful transmission
        let hashToSend = currentHash

        // Update display types in the state before sending (handles cached/throttled data)
        let updatedState = updateDisplayTypesInState(state)

        // Log connection health status if we have failures
        if failedSendCount > 0 {
            let timeString: String
            if let lastSuccess = lastSuccessfulSendTime {
                let timeSince = Date().timeIntervalSince(lastSuccess)
                timeString = "\(Int(timeSince))s"
            } else {
                timeString = "never"
            }
            debug(
                .watchManager,
                "[\(formatTimeForLog())] Garmin: Broadcasting with \(failedSendCount) recent failures. Last success: \(timeString) ago"
            )
        }

        let watchface = currentWatchface
        let datafield = currentGarminSettings.datafield

        watchApps.forEach { app in
            let isWatchfaceApp = app.uuid == watchface.watchfaceUUID
            let isDatafieldApp = app.uuid == datafield.datafieldUUID

            // 1. If it's a datafield, ALWAYS send (no status check)
            if isDatafieldApp {
                debug(.watchManager, "[\(formatTimeForLog())] Garmin: Sending to datafield \(app.uuid!) (no status check)")
                // Store hash to mark as sent on successful send
                currentSendHash = hashToSend
                sendMessage(updatedState, to: app)
                return
            }

            // 2. If it's a watchface and data is disabled, skip
            if isWatchfaceApp, !isWatchfaceDataEnabled {
                debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, skipping")
                return
            }

            // 3. For watchface with data enabled, do normal status check
            // Replace lines 1179-1199 in your GarminManager.swift with this:

            // 3. For watchface with data enabled, check cache first then send
            let appUUID = app.uuid!.uuidString

            // Check cache first
            appStatusCacheLock.lock()
            let cachedStatus = appInstallationCache[appUUID]
            appStatusCacheLock.unlock()

            // If we have fresh cache data (< 60s old), use it
            if let cached = cachedStatus, Date().timeIntervalSince(cached.lastChecked) < appStatusCacheTimeout {
                if cached.status.shouldSendData {
                    debug(
                        .watchManager,
                        "[\(formatTimeForLog())] Garmin: Sending to watchface \(app.uuid!) (cached: \(cached.status))"
                    )
                    currentSendHash = hashToSend
                    sendMessage(updatedState, to: app)
                } else {
                    debugGarmin(
                        "[\(formatTimeForLog())] Garmin: Skipping watchface \(app.uuid!) (cached: not installed)"
                    )
                }
            } else {
                // Cache miss or stale - send optimistically and update cache in background
                debug(
                    .watchManager,
                    "[\(formatTimeForLog())] Garmin: Sending to watchface \(app.uuid!) (optimistic - checking status async)"
                )
                currentSendHash = hashToSend
                sendMessage(updatedState, to: app)

                // Update cache in background with connection awareness
                connectIQ?.getAppStatus(app) { [weak self] status in
                    guard let self = self else { return }
                    self.updateAppStatusCache(app: app, isInstalled: status?.isInstalled == true)
                }
            }
        }
    }

    /// Updates display type fields in the state array/object with current settings
    /// - Parameter state: The state object (either array or dict) to update
    /// - Returns: Updated state with current displayPrimaryAttributeChoice and displaySecondaryAttributeChoice
    private func updateDisplayTypesInState(_ state: Any) -> Any {
        let displayType1 = currentGarminSettings.primaryAttributeChoice.rawValue
        let displayType2 = currentGarminSettings.secondaryAttributeChoice.rawValue

        // Handle array of states (normal case)
        if var stateArray = state as? [[String: Any]] {
            // Only update the first element (index 0) which contains extended data
            if !stateArray.isEmpty {
                stateArray[0]["displayPrimaryAttributeChoice"] = displayType1
                stateArray[0]["displaySecondaryAttributeChoice"] = displayType2
            }
            return stateArray
        }

        // Handle single state dict (shouldn't happen but be safe)
        if var stateDict = state as? [String: Any] {
            stateDict["displayPrimaryAttributeChoice"] = displayType1
            stateDict["displaySecondaryAttributeChoice"] = displayType2
            return stateDict
        }

        // Return unchanged if unexpected type
        return state
    }

    // MARK: - App Status Cache Management

    /// Updates the installation status cache for a given app UUID
    /// Updates the installation status cache for a given app with connection awareness
    private func updateAppStatusCache(app: IQApp, isInstalled: Bool) {
        guard let appUUID = app.uuid else { return }

        // Check if any device is actually connected using our tracked states
        let deviceConnected = devices.contains { (device: IQDevice) in
            if let deviceUUID = device.uuid {
                let trackedStatus = deviceConnectionStates[deviceUUID]
                return trackedStatus == .connected
            }
            return false
        }

        appStatusCacheLock.lock()
        defer { appStatusCacheLock.unlock() }

        let newStatus: AppCacheStatus = {
            if isInstalled {
                return .installed
            } else if deviceConnected {
                // Device is connected, so "not installed" is likely accurate
                return .notInstalled
            } else {
                // Device not connected - don't trust "not installed" result
                debugGarmin(
                    "[\(formatTimeForLog())] Garmin: Skipping cache update for \(appUUID) - device not connected"
                )
                return .unknown
            }
        }()

        // Only update cache if we have meaningful information
        if newStatus != .unknown || appInstallationCache[appUUID.uuidString] == nil {
            appInstallationCache[appUUID.uuidString] = (status: newStatus, lastChecked: Date())
            debugGarmin(
                "[\(formatTimeForLog())] Garmin: Updated app cache - \(appUUID) is \(newStatus)"
            )
        }
    }

    /// Returns true if we should prepare and send data
    /// True if: datafield exists OR (watchface exists AND data is enabled)
    /// False only if: no apps at all OR (only watchface AND data disabled)
    private func areAppsLikelyInstalled() -> Bool {
        let watchface = currentWatchface
        let datafield = currentGarminSettings.datafield

        // If datafield UUID exists, ALWAYS return true
        if datafield.datafieldUUID != nil {
            return true // Datafield exists, always send data
        }

        // No datafield, check watchface
        if watchface.watchfaceUUID != nil {
            // Watchface exists, check if data is enabled
            if !isWatchfaceDataEnabled {
                debugGarmin("[\(formatTimeForLog())] Garmin: ⏩ Skipping - only watchface exists and data disabled")
                return false
            }
            return true // Watchface exists and data enabled
        }

        // No apps configured at all
        debugGarmin("[\(formatTimeForLog())] Garmin: ⏩ Skipping - no apps configured")
        return false
    }

    // MARK: - GarminManager Conformance

    /// Prompts the user to select one or more Garmin devices, returning a publisher that emits
    /// the final array of selected devices once the user finishes selection.
    /// - Returns: An `AnyPublisher` emitting `[IQDevice]` on success, or empty array on error/timeout.
    func selectDevices() -> AnyPublisher<[IQDevice], Never> {
        Future { [weak self] promise in
            guard let self = self else {
                // If self is gone, just resolve with an empty array
                promise(.success([]))
                return
            }
            // Store the promise so we can fulfill it when the user selects devices
            self.deviceSelectionPromise = promise

            // Show Garmin's default device selection UI
            self.connectIQ?.showDeviceSelection()
        }
        .timeout(.seconds(120), scheduler: DispatchQueue.main)
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    /// Updates the manager's list of devices, typically after user selection or manual changes.
    /// - Parameter devices: The new array of `IQDevice` objects to track.
    func updateDeviceList(_ devices: [IQDevice]) {
        self.devices = devices
    }

    /// Converts the given JSON data into an NSDictionary and sends it to all known watch apps.
    /// Only used for throttled updates (IOB, DataType changes)
    /// - Parameter data: JSON-encoded data representing the latest watch state.
    func sendWatchStateData(_ data: Data) {
        sendWatchStateDataWithThrottle(data)
    }

    /// Sends watch state data immediately, bypassing the 30-second throttling
    /// Used for critical updates like determinations, glucose deletions, and status requests
    private func sendWatchStateDataImmediately(_ data: Data) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            debugGarmin("Garmin: Invalid JSON for immediate watch-state data")
            return
        }

        if debugWatchState {
            if let dict = jsonObject as? NSDictionary {
                debugGarmin("Garmin: Immediately sending watch state dictionary with \(dict.count) fields (no throttle)")
            } else if let array = jsonObject as? NSArray {
                debugGarmin("Garmin: Immediately sending watch state array with \(array.count) entries (no throttle)")
            }
        }

        // Directly broadcast without going through the throttled subject
        broadcastStateToWatchApps(jsonObject)
    }

    // Track current send trigger for debugging (thread-safe)
    private let triggerLock = OSAllocatedUnfairLock()
    private var _currentSendTrigger: String = "Unknown"

    private var currentSendTrigger: String {
        get { triggerLock.withLock { _currentSendTrigger } }
        set { triggerLock.withLock { _currentSendTrigger = newValue } }
    }

    // Track hash of data currently being sent (thread-safe)
    private let sendHashLock = OSAllocatedUnfairLock()
    private var _currentSendHash: Int?

    private var currentSendHash: Int? {
        get { sendHashLock.withLock { _currentSendHash } }
        set { sendHashLock.withLock { _currentSendHash = newValue } }
    }

    // Track connection health
    private var lastSuccessfulSendTime: Date?
    private var failedSendCount = 0
    private var connectionAlertShown = false

    // Manual throttle for updates - using DispatchWorkItem instead of Timer
    private var throttleWorkItem: DispatchWorkItem?
    private var pendingThrottledData: Data?

    // Combine subject for 10s throttled Determinations
    private let determinationSubject = PassthroughSubject<Data, Never>()

    // MARK: - Helper: Sending Messages

    /// Sends a message to a given IQApp with optional progress and completion callbacks.
    /// - Parameters:
    ///   - msg: The dictionary to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    private func sendMessage(_ msg: Any, to app: IQApp) {
        // Check if this is the watchface app
        let watchface = currentWatchface
        let isWatchfaceApp = app.uuid == watchface.watchfaceUUID

        // Skip sending if data is disabled AND this is the watchface app
        if !isWatchfaceDataEnabled, isWatchfaceApp {
            debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, not sending message to watchface")
            return
        }

        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in
                // Optionally track progress here
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.failedSendCount = 0
                    self.lastSuccessfulSendTime = Date()
                    self.connectionAlertShown = false // Reset alert flag on success

                    // Mark hash as sent only after successful transmission
                    if let sentHash = self.currentSendHash {
                        self.lastSentHashLock.lock()
                        self.lastSentDataHash = sentHash
                        self.lastSentHashLock.unlock()
                    }

                    debug(
                        .watchManager,
                        "[\(self.formatTimeForLog())] Garmin: Successfully sent message to \(app.uuid!) [Trigger: \(self.currentSendTrigger)]"
                    )
                default:
                    self.failedSendCount += 1
                    debug(
                        .watchManager,
                        "[\(self.formatTimeForLog())] Garmin: FAILED to send to \(app.uuid!) [Trigger: \(self.currentSendTrigger)] (Failure #\(self.failedSendCount))"
                    )

                    // After 3 consecutive failures, show alert (but only once)
                    if self.failedSendCount >= 3, !self.connectionAlertShown {
                        self.showConnectionLostAlert()
                        self.connectionAlertShown = true
                    }
                }
            }
        )
    }

    /// Shows an alert when Garmin connection is lost
    private func showConnectionLostAlert() {
        let messageCont = MessageContent(
            content: "Unable to send data to Garmin device.\n\nPlease check:\n• Bluetooth is enabled\n• Watch is in range\n• Watch is powered on\n• Watchface/Datafield is installed",
            type: .warning,
            subtype: .misc,
            title: "Garmin Connection Lost"
        )
        router.alertMessage.send(messageCont)

        debugGarmin("[\(formatTimeForLog())] Garmin: Connection lost alert shown to user")
    }
}

// MARK: - Extensions

extension BaseGarminManager: IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {
    // MARK: - IQUIOverrideDelegate

    /// Called if the Garmin Connect Mobile app is not installed or otherwise not available.
    /// Typically, you would show an alert or prompt the user to install the app from the store.
    func needsToInstallConnectMobile() {
        debug(.apsManager, "Garmin is not available")
        let messageCont = MessageContent(
            content: "The app Garmin Connect must be installed to use Trio.\nGo to the App Store to download it.",
            type: .warning,
            subtype: .misc,
            title: "Garmin is not available"
        )
        router.alertMessage.send(messageCont)
    }

    // MARK: - IQDeviceEventDelegate

    /// Called whenever the status of a registered Garmin device changes (e.g., connected, not found, etc.).
    /// - Parameters:
    ///   - device: The device whose status has changed.
    ///   - status: The new status for the device.
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        // Track the current status for connection-aware caching
        if let deviceUUID = device.uuid {
            deviceConnectionStates[deviceUUID] = status
        }

        switch status {
        case .invalidDevice:
            debugGarmin("[\(formatTimeForLog())] Garmin: invalidDevice (\(device.uuid!))")
        case .bluetoothNotReady:
            debugGarmin("[\(formatTimeForLog())] Garmin: bluetoothNotReady (\(device.uuid!))")
        case .notFound:
            debugGarmin("[\(formatTimeForLog())] Garmin: notFound (\(device.uuid!))")
        case .notConnected:
            debugGarmin("[\(formatTimeForLog())] Garmin: notConnected (\(device.uuid!))")
        case .connected:
            debugGarmin("[\(formatTimeForLog())] Garmin: connected (\(device.uuid!))")
        @unknown default:
            debugGarmin("[\(formatTimeForLog())] Garmin: unknown state (\(device.uuid!))")
        }
    }

    // MARK: - IQAppMessageDelegate

    /// Called when a message arrives from a Garmin watch app (watchface or data field).
    /// If the watch requests a "status" update, we call appropriate setup method
    /// based on watchface setting and re-send the watch state data.
    /// - Parameters:
    ///   - message: The message content from the watch app.
    ///   - app: The watch app sending the message.
    /// Handle messages from watch apps
    /// Always processes datafield messages, checks settings for watchface
    func receivedMessage(_ message: Any, from app: IQApp) {
        debugGarmin("[\(formatTimeForLog())] Garmin: Received message \(message) from app \(app.uuid!)")

        let validUUIDs = Set([currentWatchface.watchfaceUUID, currentGarminSettings.datafield.datafieldUUID].compactMap { $0 })

        // Must be from a configured app
        guard validUUIDs.contains(app.uuid!) else {
            debugGarmin("[\(formatTimeForLog())] ⏭️ Ignoring message from unregistered app: \(app.uuid!)")
            return
        }

        // If from datafield, mark as installed in cache (confirms installation)
        if app.uuid == currentGarminSettings.datafield.datafieldUUID {
            updateAppStatusCache(app: app, isInstalled: true)
            debugGarmin("[\(formatTimeForLog())] Garmin: Datafield confirmed installed via status message")
        }

        // All messages are "status" requests - ignore them (timer keeps watchface/datafield alive, no response needed)
        debugGarmin("[\(formatTimeForLog())] ⏭️ Ignoring status request - apps receive proactive updates")
    }
}

// MARK: - SettingsObserver

extension BaseGarminManager: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        debug(.watchManager, "🔔 settingsDidChange triggered")

        // Check what changed by comparing with stored previous values
        let watchfaceChanged = previousGarminSettings.watchface != settings.garminSettings.watchface
        let datafieldChanged = previousGarminSettings.datafield != settings.garminSettings.datafield
        let dataType1Changed = previousGarminSettings.primaryAttributeChoice != settings.garminSettings.primaryAttributeChoice
        let dataType2Changed = previousGarminSettings.secondaryAttributeChoice != settings.garminSettings.secondaryAttributeChoice
        let unitsChanged = units != settings.units
        let enabledChanged = previousGarminSettings.isWatchfaceDataEnabled != settings.garminSettings.isWatchfaceDataEnabled

        // Debug what changed BEFORE updating stored values
        if watchfaceChanged {
            debug(
                .watchManager,
                "Garmin: Watchface changed from \(previousGarminSettings.watchface.displayName) to \(settings.garminSettings.watchface.displayName). Re-registering devices only, no data update"
            )
        }

        if datafieldChanged {
            debug(
                .watchManager,
                "Garmin: Datafield changed from \(previousGarminSettings.datafield.displayName) to \(settings.garminSettings.datafield.displayName). Re-registering devices only, no data update"
            )
        }

        if dataType1Changed {
            debug(
                .watchManager,
                "Garmin: Primary attribute choice changed from \(previousGarminSettings.primaryAttributeChoice.displayName) to \(settings.garminSettings.primaryAttributeChoice.displayName)"
            )
        }

        if dataType2Changed {
            debug(
                .watchManager,
                "Garmin: Secondary attribute choice changed from \(previousGarminSettings.secondaryAttributeChoice.displayName) to \(settings.garminSettings.secondaryAttributeChoice.displayName)"
            )
        }

        if unitsChanged {
            debugGarmin("Garmin: Units changed - immediate update required")
        }

        if enabledChanged {
            debug(
                .watchManager,
                "Garmin: Watchface data enabled changed from \(previousGarminSettings.isWatchfaceDataEnabled) to \(settings.garminSettings.isWatchfaceDataEnabled)"
            )

            // Re-register devices to add/remove watchface app based on enabled state
            registerDevices(devices)

            if !settings.garminSettings.isWatchfaceDataEnabled { // ← REVERSED LOGIC
                debugGarmin("Garmin: Watchface app unregistered, datafield continues")
            } else {
                debugGarmin("Garmin: Watchface app re-registered - sending immediate update")
            }
        }

        // NOW update stored values AFTER logging the changes
        units = settings.units
        previousGarminSettings = settings.garminSettings

        // Handle watchface or datafield change - ONLY re-register, NO data send
        if watchfaceChanged || datafieldChanged {
            // Clear cached determination data after watchface/datafield change
            cachedDeterminationData = nil
            lastWatchfaceChangeTime = Date()

            // Clear hash cache since data format differs between watchfaces
            hashLock.lock()
            lastPreparedDataHash = nil
            lastPreparedWatchState = nil
            hashLock.unlock()

            debugGarmin("Garmin: Cleared cached determination data due to watchface change")

            registerDevices(devices)
            debugGarmin("Garmin: Re-registered devices for new watchface UUID")
            // NO data send here - wait for watch to request or next regular update
        }

        // Determine which type of update is needed (if any)
        let needsImmediateUpdate = (
            unitsChanged ||
                (enabledChanged && settings.garminSettings.isWatchfaceDataEnabled) // ← REVERSED LOGIC
        ) &&
            !watchfaceChanged && !datafieldChanged // Don't send if only watchface or datafield changed

        let needsThrottledUpdate = (dataType1Changed || dataType2Changed) &&
            !watchfaceChanged && !datafieldChanged // Don't send if only watchface or datafield changed

        // Send immediate update for critical changes
        if needsImmediateUpdate {
            Task {
                // Skip if no apps are installed (based on cache)
                guard self.areAppsLikelyInstalled() else {
                    debugGarmin("⏩ Skipping immediate settings update - no apps installed (cached)")
                    return
                }

                do {
                    // Try to use cached determination data first to avoid CoreData staleness
                    if let cachedData = self.cachedDeterminationData {
                        self.currentSendTrigger = "Settings-Units/Re-enable"

                        // Cancel any pending throttled send since we're sending immediately
                        self.throttleWorkItem?.cancel()
                        self.throttleWorkItem = nil
                        self.pendingThrottledData = nil
                        self.throttledUpdatePending = false

                        debugGarmin("Garmin: Using cached determination data for immediate settings update")
                        self.sendWatchStateDataImmediately(cachedData)
                        self.lastImmediateSendTime = Date()
                        debugGarmin("Garmin: Immediate update sent for units/re-enable change (from cache)")
                    } else {
                        // Fallback to fresh query if no cache available
                        let watchState = try await self.setupGarminWatchState(triggeredBy: "Settings-Units/Re-enable")
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.currentSendTrigger = "Settings-Units/Re-enable"

                        // Cancel any pending throttled send since we're sending immediately
                        self.throttleWorkItem?.cancel()
                        self.throttleWorkItem = nil
                        self.pendingThrottledData = nil
                        self.throttledUpdatePending = false

                        self.sendWatchStateDataImmediately(watchStateData)
                        self.lastImmediateSendTime = Date()
                        debugGarmin("Garmin: Immediate update sent for units/re-enable change (fresh query)")
                    }
                } catch {
                    debug(
                        .watchManager,
                        "\(DebuggingIdentifiers.failed) Failed to send immediate update after settings change: \(error)"
                    )
                }
            }
        }
        // Send throttled update for data type changes
        else if needsThrottledUpdate {
            Task {
                // Skip if no apps are installed (based on cache)
                guard self.areAppsLikelyInstalled() else {
                    debugGarmin("⏩ Skipping throttled settings update - no apps installed (cached)")
                    return
                }

                // Use cached data if available (display types will be updated at send time)
                if let cachedData = self.cachedDeterminationData {
                    self.currentSendTrigger = "Settings-DataType"
                    self.sendWatchStateDataWithThrottle(cachedData)
                    debugGarmin("Garmin: Throttled update queued for data type change (10s) - using cached data")
                } else {
                    // No cached data - prepare fresh (shouldn't happen often)
                    do {
                        let watchState = try await self.setupGarminWatchState(triggeredBy: "Settings-DataType")
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.currentSendTrigger = "Settings-DataType"
                        self.sendWatchStateDataWithThrottle(watchStateData)
                        debugGarmin("Garmin: Throttled update queued for data type change (10s) - fresh data")
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Failed to send throttled update after settings change: \(error)"
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Validation Helpers Extension

extension BaseGarminManager {
    // MARK: - Glucose Validation

    /// Validates glucose reading and returns the value if valid
    /// - Parameters:
    ///   - glucose: GlucoseStored object
    ///   - maxAgeMinutes: Maximum age in minutes (default: 15)
    /// - Returns: Valid glucose value (Int16), or nil if invalid
    private func validateGlucoseReading(
        _ glucose: GlucoseStored?,
        maxAgeMinutes: Double = 15
    ) -> Int16? {
        guard let glucose = glucose,
              let glucoseDate = glucose.date
        else {
            return nil
        }

        let age = Date().timeIntervalSince(glucoseDate) / 60
        guard age <= maxAgeMinutes else {
            return nil
        }

        // glucose.glucose is already Int16
        let glucoseValue = glucose.glucose
        guard glucoseValue >= 0, glucoseValue <= 500 else {
            return nil
        }

        return glucoseValue
    }

    /// Validates glucose reading with trend information
    /// - Parameters:
    ///   - glucose: GlucoseStored object
    ///   - previousGlucose: Previous GlucoseStored for delta calculation
    ///   - maxAgeMinutes: Maximum age in minutes (default: 15)
    /// - Returns: Tuple of (value, delta, direction) if valid, or nil
    private func validateGlucoseWithTrend(
        _ glucose: GlucoseStored?,
        previousGlucose: GlucoseStored?,
        maxAgeMinutes: Double = 15
    ) -> (value: Int16, delta: Int16?, direction: String)? {
        guard let validValue = validateGlucoseReading(glucose, maxAgeMinutes: maxAgeMinutes),
              let glucose = glucose
        else {
            return nil
        }

        // Calculate delta if previous reading exists
        let delta: Int16? = {
            guard let prev = previousGlucose else { return 0 }
            let deltaValue = glucose.glucose - prev.glucose
            guard deltaValue >= -100, deltaValue <= 100 else { return nil }
            return deltaValue
        }()

        let direction = glucose.direction ?? "--"

        return (value: validValue, delta: delta, direction: direction)
    }

    // MARK: - Data Freshness Validation

    /// Validates determination data freshness
    /// - Parameters:
    ///   - determination: OrefDetermination object
    ///   - maxAgeMinutes: Maximum age in minutes (default: 15)
    /// - Returns: True if fresh, false otherwise
    private func isDeterminationFresh(
        _ determination: OrefDetermination?,
        maxAgeMinutes: Double = 15
    ) -> Bool {
        guard let determination = determination else { return false }

        // OrefDetermination uses timestamp (not date)
        guard let timestamp = determination.timestamp else { return false }

        let age = Date().timeIntervalSince(timestamp) / 60
        return age <= maxAgeMinutes
    }

    /// Validates timestamp freshness
    /// - Parameters:
    ///   - date: Date to validate
    ///   - maxAgeMinutes: Maximum age in minutes
    /// - Returns: True if fresh, false otherwise
    private func isDataFresh(
        _ date: Date?,
        maxAgeMinutes: Double
    ) -> Bool {
        guard let date = date else {
            return false
        }

        let age = Date().timeIntervalSince(date) / 60
        return age <= maxAgeMinutes
    }

    // MARK: - App Configuration Validation

    /// Validation result for app configuration
    private struct AppValidationResult {
        let shouldProceed: Bool
        let reason: String
    }

    /// Validates app installation and configuration status
    /// - Returns: ValidationResult indicating whether to proceed
    private func validateAppConfiguration() -> AppValidationResult {
        let garminSettings = settingsManager.settings.garminSettings

        // Check if datafield is configured (not .none)
        let hasDatafield = garminSettings.datafield != .none

        // If datafield exists, always proceed (datafield always sends)
        if hasDatafield {
            return AppValidationResult(
                shouldProceed: true,
                reason: "Datafield configured"
            )
        }

        // Only watchface, check if data is enabled
        if !garminSettings.isWatchfaceDataEnabled {
            return AppValidationResult(
                shouldProceed: false,
                reason: "Watchface data transmission disabled"
            )
        }

        return AppValidationResult(
            shouldProceed: true,
            reason: "Valid app configuration"
        )
    }

    private func shouldSendData() -> Bool {
        let garminSettings = settingsManager.settings.garminSettings

        // Case 1: Datafield configured - ALWAYS send
        if garminSettings.datafield != .none {
            return true
        }

        // Case 2: Only watchface - check if enabled
        return garminSettings.isWatchfaceDataEnabled
    }

    // MARK: - Numeric Value Validation

    /// Validates and formats numeric value for display
    /// - Parameters:
    ///   - value: Optional double value
    ///   - defaultValue: Default value if nil or invalid
    ///   - decimalPlaces: Number of decimal places (default: 1)
    /// - Returns: Formatted numeric value
    private func validateAndFormatNumeric(
        _ value: Double?,
        defaultValue: Double = 0.0,
        decimalPlaces: Int = 1
    ) -> Double {
        guard let value = value, value.isFinite else {
            return defaultValue
        }

        return value.roundedDouble(toPlaces: decimalPlaces)
    }

    /// Validates COB value from Int16 (CoreData storage type)
    /// - Parameter cob: COB value (Int16)
    /// - Returns: Valid COB value or 0
    private func validateCOB(_ cob: Int16) -> Double {
        let cobDouble = Double(cob)
        guard cobDouble >= 0 else {
            return 0
        }
        return cobDouble
    }

    /// Validates COB value from Decimal
    /// - Parameter cob: COB value (Decimal from CoreData)
    /// - Returns: Valid COB value or 0
    private func validateCOB(_ cob: Decimal) -> Double {
        let cobDouble = Double(truncating: cob as NSNumber)
        guard cobDouble.isFinite, !cobDouble.isNaN, cobDouble >= 0 else {
            return 0
        }
        return cobDouble.roundedDouble(toPlaces: 0)
    }

    /// Validates IOB value
    /// - Parameter iob: IOB value (Decimal)
    /// - Returns: Valid IOB value or 0.0
    private func validateIOB(_ iob: Decimal) -> Double {
        let iobDouble = Double(truncating: iob as NSNumber)
        return validateAndFormatNumeric(iobDouble, defaultValue: 0.0, decimalPlaces: 1)
    }

    /// Validates sensitivity ratio value
    /// - Parameter sensRatio: Sensitivity ratio NSNumber
    /// - Returns: Valid sensitivity ratio or 1.0 (default)
    private func validateSensRatio(_ sensRatio: NSNumber?) -> Double {
        guard let sensRatio = sensRatio else { return 1.0 }
        let sensRatioDouble = Double(truncating: sensRatio as NSNumber)
        guard sensRatioDouble.isFinite, !sensRatioDouble.isNaN, sensRatioDouble > 0 else {
            return 1.0
        }
        return sensRatioDouble.roundedDouble(toPlaces: 2)
    }

    /// Validates ISF (insulin sensitivity factor) value
    /// - Parameter insulinSensitivity: ISF value as NSNumber
    /// - Returns: Valid ISF value (Int16) or nil
    private func validateISF(_ insulinSensitivity: NSNumber?) -> Int16? {
        guard let isf = insulinSensitivity as? Int16 else { return nil }
        guard isf > 0, isf <= 300 else { return nil }
        return isf
    }

    /// Validates eventual BG value
    /// - Parameter eventualBG: Eventual BG value as NSNumber
    /// - Returns: Valid eventual BG value (Int16) or nil
    private func validateEventualBG(_ eventualBG: NSNumber?) -> Int16? {
        guard let bg = eventualBG as? Int16 else { return nil }
        guard bg >= 0, bg <= 500 else { return nil }
        return bg
    }

    // MARK: - Settings Change Validation

    /// Settings change detection result
    struct SettingsChange {
        let watchfaceChanged: Bool
        let datafieldChanged: Bool
        let dataType1Changed: Bool
        let dataType2Changed: Bool
        let unitsChanged: Bool
        let enabledChanged: Bool
    }

    /// Detects which settings have changed
    /// - Parameter newSettings: New settings to compare against
    /// - Returns: SettingsChange struct with boolean flags for each change
    private func detectSettingsChanges(_ newSettings: TrioSettings) -> SettingsChange {
        let oldSettings = previousGarminSettings
        let newGarmin = newSettings.garminSettings

        return SettingsChange(
            watchfaceChanged: oldSettings.watchface != newGarmin.watchface,
            datafieldChanged: oldSettings.datafield != newGarmin.datafield,
            dataType1Changed: oldSettings.primaryAttributeChoice != newGarmin.primaryAttributeChoice,
            dataType2Changed: oldSettings.secondaryAttributeChoice != newGarmin.secondaryAttributeChoice,
            unitsChanged: units != newSettings.units,
            enabledChanged: oldSettings.isWatchfaceDataEnabled != newGarmin.isWatchfaceDataEnabled
        )
    }

    // MARK: - Cache Validation

    /// Checks if app installation cache is valid
    /// - Parameter appUUID: UUID of the app to check
    /// - Returns: Cached status if valid, nil otherwise
    private func getCachedAppStatus(_ appUUID: String) -> Bool? {
        appStatusCacheLock.lock()
        defer { appStatusCacheLock.unlock() }

        guard let cached = appInstallationCache[appUUID] else {
            return nil
        }

        let age = Date().timeIntervalSince(cached.lastChecked)
        guard age < appStatusCacheTimeout else {
            appInstallationCache.removeValue(forKey: appUUID)
            return nil
        }

        return cached.status.shouldSendData
    }

    /// Updates app installation cache
    /// - Parameters:
    ///   - appUUID: UUID of the app
    ///   - isInstalled: Installation status
    private func updateAppStatusCache(_ appUUID: String, isInstalled: Bool) {
        appStatusCacheLock.lock()
        defer { appStatusCacheLock.unlock() }

        appInstallationCache[appUUID] = (status: isInstalled ? .installed : .notInstalled, lastChecked: Date()) }
}
