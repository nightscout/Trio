import Combine
import ConnectIQ
import CoreData
import Foundation
import Swinject

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
///  - Generating & sending watch-state updates (glucose, IOB, COB, etc.) to Garmin watch apps
///  - Throttling updates to prevent excessive watch communication
///  - Supporting multiple watchface formats (SwissAlpine and Trio)
final class BaseGarminManager: NSObject, GarminManager, Injectable, @unchecked Sendable {
    // MARK: - Dependencies & Properties

    @Injected() private var notificationCenter: NotificationCenter!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var iobService: IOBService!

    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    private let router: Router
    private let connectIQ = ConnectIQ.sharedInstance()
    private var watchApps: [IQApp] = []
    private var cancellables = Set<AnyCancellable>()
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

    /// Enable/disable debug logging for watch state data being sent
    private let debugWatchState = true

    /// Enable/disable general Garmin operation logging
    private let debugGarmin = true

    /// Helper method for conditional Garmin debug logging
    private func debugGarmin(_ message: String) {
        guard debugGarmin else { return }
        debug(.watchManager, message)
    }

    private var lastImmediateSendTime: Date?
    private var throttledUpdatePending = false
    private var cachedDeterminationData: Data?
    private var lastWatchfaceChangeTime: Date?

    /// Array of Garmin `IQDevice` objects currently tracked.
    /// Changing this property triggers re-registration and updates persisted devices.
    private(set) var devices: [IQDevice] = [] {
        didSet {
            persistedDevices = devices.map(GarminDevice.init)
            registerDevices(devices)
        }
    }

    private var units: GlucoseUnits = .mgdL
    private var previousWatchface: GarminWatchface = .trio
    private var previousDataType1: GarminDataType1 = .cob
    private var previousDataType2: GarminDataType2 = .tbr
    private var previousDisableWatchfaceData: Bool = false

    private let queue = DispatchQueue(label: "BaseGarminManager.queue", qos: .utility)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    let backgroundContext = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    private var currentSendTrigger: String = "Unknown"
    private var lastSuccessfulSendTime: Date?
    private var failedSendCount = 0
    private var connectionAlertShown = false
    private var throttleTimer30s: Timer?
    private var pendingThrottledData30s: Data?
    private let determinationSubject = PassthroughSubject<Data, Never>()

    // MARK: - Initialization

    /// Creates a new `BaseGarminManager`, injecting required services, restoring any persisted devices,
    /// and setting up watchers for data changes (glucose, IOB, determinations).
    /// - Parameter resolver: Swinject resolver for injecting dependencies.
    init(resolver: Resolver) {
        router = resolver.resolve(Router.self)!
        super.init()
        injectServices(resolver)

        connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)

        restoreDevices()
        subscribeToOpenFromGarminConnect()
        subscribeToDeterminationThrottle()

        units = settingsManager.settings.units
        previousWatchface = settingsManager.settings.garminWatchface
        previousDataType1 = settingsManager.settings.garminDataType1
        previousDataType2 = settingsManager.settings.garminDataType2
        previousDisableWatchfaceData = settingsManager.settings.garminDisableWatchfaceData

        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        subscribeToGlucoseUpdates()
        subscribeToIOBUpdates()
        registerCoreDataHandlers()
    }

    // MARK: - Helper Properties

    /// Gets the current Garmin watchface setting
    private var currentWatchface: GarminWatchface {
        settingsManager.settings.garminWatchface
    }

    /// Gets the current Garmin data type 1 setting
    private var currentDataType1: GarminDataType1 {
        settingsManager.settings.garminDataType1
    }

    /// Gets the current Garmin data type 2 setting
    private var currentDataType2: GarminDataType2 {
        settingsManager.settings.garminDataType2
    }

    /// Checks if watchface data transmission is disabled
    private var isWatchfaceDataDisabled: Bool {
        settingsManager.settings.garminDisableWatchfaceData
    }

    // MARK: - Subscriptions

    /// Subscribes to glucose storage updates. Only sends immediate updates if the loop is stale (>8 minutes).
    private func subscribeToGlucoseUpdates() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }

                #if targetEnvironment(simulator)
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                Task {
                    do {
                        let determinationIds = try await self.determinationStorage.fetchLastDeterminationObjectID(
                            predicate: NSPredicate.enactedDetermination
                        )

                        let loopAge = await self.getLoopAge(determinationIds)

                        if loopAge > 480 {
                            let watchface = self.currentWatchface
                            if watchface == .swissalpine {
                                let watchStates = try await self.setupGarminSwissAlpineWatchState()
                                let watchStateData = try JSONEncoder().encode(watchStates)
                                self.currentSendTrigger = "Glucose-Stale-Loop (\(Int(loopAge / 60))m)"
                                self.sendWatchStateDataImmediately(watchStateData)
                                self.lastImmediateSendTime = Date()
                            } else {
                                let watchState = try await self.setupGarminTrioWatchState()
                                let watchStateData = try JSONEncoder().encode(watchState)
                                self.currentSendTrigger = "Glucose-Stale-Loop (\(Int(loopAge / 60))m)"
                                self.sendWatchStateDataImmediately(watchStateData)
                                self.lastImmediateSendTime = Date()
                            }
                            debug(
                                .watchManager,
                                "[\(self.formatTimeForLog())] Garmin: Glucose sent immediately - loop age > 8 min (\(Int(loopAge / 60))m)"
                            )
                        } else {
                            debug(
                                .watchManager,
                                "[\(self.formatTimeForLog())] Garmin: Glucose skipped - loop age \(Int(loopAge / 60))m < 8m"
                            )
                        }
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Error checking loop age: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)
    }

    /// Subscribes to IOB service updates and publishes to the throttled determination pipeline.
    private func subscribeToIOBUpdates() {
        iobService.iobPublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }

                #if targetEnvironment(simulator)
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                Task {
                    do {
                        let watchface = self.currentWatchface
                        if watchface == .swissalpine {
                            let watchStates = try await self.setupGarminSwissAlpineWatchState()
                            let watchStateData = try JSONEncoder().encode(watchStates)
                            self.currentSendTrigger = "IOB-Update"
                            self.determinationSubject.send(watchStateData)
                        } else {
                            let watchState = try await self.setupGarminTrioWatchState()
                            let watchStateData = try JSONEncoder().encode(watchState)
                            self.currentSendTrigger = "IOB-Update"
                            self.determinationSubject.send(watchStateData)
                        }
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Error updating watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)
    }

    /// Sets up handlers for OrefDetermination entity changes in CoreData.
    /// When determinations change, data is published to the throttled pipeline.
    private func registerCoreDataHandlers() {
        coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .sink { [weak self] _ in
                guard let self = self else { return }

                #if targetEnvironment(simulator)
                #else
                    guard !self.devices.isEmpty else { return }
                #endif

                Task {
                    do {
                        let watchface = self.currentWatchface
                        if watchface == .swissalpine {
                            let watchStates = try await self.setupGarminSwissAlpineWatchState()
                            let watchStateData = try JSONEncoder().encode(watchStates)
                            self.currentSendTrigger = "Determination"
                            self.determinationSubject.send(watchStateData)
                        } else {
                            let watchState = try await self.setupGarminTrioWatchState()
                            let watchStateData = try JSONEncoder().encode(watchState)
                            self.currentSendTrigger = "Determination"
                            self.determinationSubject.send(watchStateData)
                        }
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Failed to update watch state: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)
    }

    /// Calculates the age of the most recent loop determination.
    /// - Parameter determinationIds: Array of determination object IDs to check.
    /// - Returns: Time interval in seconds since the last determination, or infinity if none found.
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

    /// Sends watch state data with 30-second throttling for status requests and settings changes.
    /// - Parameter data: JSON-encoded watch state data.
    private func sendWatchStateDataWith30sThrottle(_ data: Data) {
        pendingThrottledData30s = data

        if throttleTimer30s?.isValid == true {
            debug(
                .watchManager,
                "[\(formatTimeForLog())] Garmin: 30s throttle timer running, data updated [Trigger: \(currentSendTrigger)]"
            )
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.throttleTimer30s = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                guard let self = self,
                      let dataToSend = self.pendingThrottledData30s
                else {
                    return
                }

                if let lastImmediate = self.lastImmediateSendTime,
                   Date().timeIntervalSince(lastImmediate) < 5
                {
                    debugGarmin("[\(self.formatTimeForLog())] Garmin: 30s timer cancelled - recent determination/IOB send")
                    self.throttleTimer30s = nil
                    self.pendingThrottledData30s = nil
                    self.throttledUpdatePending = false
                    return
                }

                guard let jsonObject = try? JSONSerialization.jsonObject(with: dataToSend, options: []) else {
                    debugGarmin("[\(self.formatTimeForLog())] Garmin: Invalid JSON in 30s throttled data")
                    self.throttleTimer30s = nil
                    self.pendingThrottledData30s = nil
                    self.throttledUpdatePending = false
                    return
                }

                debugGarmin("[\(self.formatTimeForLog())] Garmin: 30s timer fired - sending collected updates")
                self.broadcastStateToWatchApps(jsonObject as Any)

                self.throttleTimer30s = nil
                self.pendingThrottledData30s = nil
                self.throttledUpdatePending = false
            }

            self.throttledUpdatePending = true
            debugGarmin("[\(self.formatTimeForLog())] Garmin: 30s throttle timer started")
        }
    }

    /// Fetches recent glucose readings from CoreData.
    /// - Parameter limit: Maximum number of glucose entries to fetch.
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
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: false,
            fetchLimit: 5
        )

        return try await backgroundContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return pumpEvents.filter { $0.tempBasal != nil }.map(\.objectID)
        }
    }

    // MARK: - Debug Logging

    /// Logs SwissAlpine format watch states for debugging.
    /// - Parameter watchStates: Array of watch state entries to log.
    private func logSwissAlpineWatchStates(_ watchStates: [GarminSwissAlpineWatchState]) {
        guard debugWatchState else { return }

        let watchface = currentWatchface
        let watchfaceUUID = watchface.watchfaceUUID?.uuidString ?? "Unknown"
        let datafieldUUID = watchface.datafieldUUID?.uuidString ?? "Unknown"

        do {
            let jsonData = try JSONEncoder().encode(watchStates)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let compactJson = jsonString.replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "  ", with: " ")

                let destinations: String
                if isWatchfaceDataDisabled {
                    destinations = "datafield \(datafieldUUID) only (watchface disabled)"
                } else {
                    destinations = "watchface \(watchfaceUUID) / datafield \(datafieldUUID)"
                }

                debug(
                    .watchManager,
                    "📱 SwissAlpine: Sending \(watchStates.count) entries to \(destinations): \(compactJson)"
                )
            }
        } catch {
            debug(.watchManager, "📱 SwissAlpine: Sending \(watchStates.count) entries (failed to encode for logging)")
        }
    }

    /// Logs Trio format watch state for debugging.
    /// - Parameter watchState: The watch state to log.
    private func logTrioWatchState(_ watchState: GarminTrioWatchState) {
        guard debugWatchState else { return }

        let watchface = currentWatchface
        let watchfaceUUID = watchface.watchfaceUUID?.uuidString ?? "Unknown"
        let datafieldUUID = watchface.datafieldUUID?.uuidString ?? "Unknown"

        do {
            let jsonData = try JSONEncoder().encode(watchState)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let compactJson = jsonString.replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "  ", with: " ")

                let destinations: String
                if isWatchfaceDataDisabled {
                    destinations = "datafield \(datafieldUUID) only (watchface disabled)"
                } else {
                    destinations = "watchface \(watchfaceUUID) / datafield \(datafieldUUID)"
                }

                debug(
                    .watchManager,
                    "📱 Trio: Sending to \(destinations): \(compactJson)"
                )
            }
        } catch {
            debug(.watchManager, "📱 Trio: Failed to encode for logging")
        }
    }

    // MARK: - Watch State Setup

    /// Builds a Trio format watch state with the latest glucose, IOB, COB, and determination data.
    /// - Returns: A `GarminTrioWatchState` containing current device and therapy information.
    func setupGarminTrioWatchState() async throws -> GarminTrioWatchState {
        #if targetEnvironment(simulator)
            let skipDeviceCheck = true
        #else
            let skipDeviceCheck = false
        #endif

        guard !devices.isEmpty || skipDeviceCheck else {
            debug(.watchManager, "⌚️⛔ Skipping setupGarminTrioWatchState - No Garmin devices connected")
            return GarminTrioWatchState()
        }

        do {
            let glucoseIds = try await fetchGlucose()
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.enactedDetermination
            )

            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)

            return await backgroundContext.perform {
                var watchState = GarminTrioWatchState()

                let iobValue = self.iobService.currentIOB ?? 0
                watchState.iob = self.iobFormatterWithOneFractionDigit(iobValue)

                if let latestDetermination = determinationObjects.first {
                    watchState.lastLoopDateInterval = latestDetermination.timestamp.map {
                        guard $0.timeIntervalSince1970 > 0 else { return 0 }
                        return UInt64($0.timeIntervalSince1970)
                    }

                    let cobNumber = NSNumber(value: latestDetermination.cob)
                    watchState.cob = Formatter.integerFormatter.string(from: cobNumber)

                    let sensRatio = latestDetermination.insulinSensitivity ?? 1
                    let currentDataType1 = self.currentDataType1
                    if currentDataType1 == .sensRatio {
                        let sensRatio = latestDetermination.sensitivityRatio ?? 1
                        watchState.sensRatio = sensRatio.description
                    }

                    let eventualBG = latestDetermination.eventualBG ?? 0
                    if self.units == .mgdL {
                        watchState.eventualBGRaw = eventualBG.description
                    } else {
                        let parsedEventualBG = Double(truncating: eventualBG).asMmolL
                        watchState.eventualBGRaw = parsedEventualBG.description
                    }

                    let insulinSensitivity = latestDetermination.insulinSensitivity ?? 0

                    if self.units == .mgdL {
                        watchState.isf = insulinSensitivity.description
                    } else {
                        let parsedIsf = Double(truncating: insulinSensitivity).asMmolL
                        watchState.isf = parsedIsf.description
                    }
                }

                guard let latestGlucose = glucoseObjects.first else {
                    self.logTrioWatchState(watchState)
                    return watchState
                }

                if self.units == .mgdL {
                    watchState.glucose = "\(latestGlucose.glucose)"
                } else {
                    let mgdlValue = Decimal(latestGlucose.glucose)
                    let latestGlucoseValue = Double(truncating: mgdlValue.asMmolL as NSNumber)
                    watchState.glucose = "\(latestGlucoseValue)"
                }

                watchState.trendRaw = latestGlucose.direction ?? "--"

                if glucoseObjects.count >= 2 {
                    var deltaValue = Decimal(glucoseObjects[0].glucose - glucoseObjects[1].glucose)

                    if self.units == .mmolL {
                        deltaValue = Double(truncating: deltaValue as NSNumber).asMmolL
                    }

                    let formattedDelta = deltaValue.description
                    watchState.delta = deltaValue < 0 ? "\(formattedDelta)" : "+\(formattedDelta)"
                }

                self.logTrioWatchState(watchState)

                return watchState
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up Garmin Trio watch state: \(error)"
            )
            throw error
        }
    }

    /// Builds a SwissAlpine format watch state array with the last 24 glucose readings and current therapy data.
    /// - Returns: An array of `GarminSwissAlpineWatchState` entries.
    func setupGarminSwissAlpineWatchState() async throws -> [GarminSwissAlpineWatchState] {
        #if targetEnvironment(simulator)
            let skipDeviceCheck = true
        #else
            let skipDeviceCheck = false
        #endif

        guard !devices.isEmpty || skipDeviceCheck else {
            debug(.watchManager, "⌚️⛔ Skipping setupGarminSwissAlpineWatchState - No Garmin devices connected")
            return []
        }

        do {
            let glucoseIds = try await fetchGlucose(limit: 24)
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.enactedDetermination
            )
            let tempBasalIds = try await fetchTempBasals()

            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)
            let tempBasalObjects: [PumpEventStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: tempBasalIds, context: backgroundContext)

            return await backgroundContext.perform {
                var watchStates: [GarminSwissAlpineWatchState] = []

                let unitsHint = self.units == .mgdL ? "mgdl" : "mmol"
                let iobValue = Double(self.iobService.currentIOB ?? 0)

                var cobValue: Double?
                var sensRatioValue: Double?
                var isfValue: Int16?
                var eventualBGValue: Int16?

                if let latestDetermination = determinationObjects.first {
                    cobValue = Double(latestDetermination.cob)

                    let currentDataType1 = self.currentDataType1
                    if currentDataType1 == .sensRatio {
                        let sensRatio = latestDetermination.sensitivityRatio ?? 1
                        sensRatioValue = Double(truncating: sensRatio as NSNumber)
                    }

                    isfValue = Int16(truncating: latestDetermination.insulinSensitivity ?? 0)
                    eventualBGValue = Int16(truncating: latestDetermination.eventualBG ?? 0)
                }

                let currentDataType2 = self.currentDataType2
                var adjustedEventualBGValue: Int16? = eventualBGValue
                if currentDataType2 == .tbr {
                    adjustedEventualBGValue = nil
                    if self.debugWatchState {
                        debug(.watchManager, "⌚️ SwissAlpine: TBR mode selected, excluding eventualBG from JSON")
                    }
                }

                var tbrValue: Double?
                if let firstTempBasal = tempBasalObjects.first,
                   let tempBasalData = firstTempBasal.tempBasal,
                   let tempRate = tempBasalData.rate
                {
                    tbrValue = Double(truncating: tempRate)

                    if self.debugWatchState {
                        debug(.watchManager, "⌚️ Current basal rate: \(tbrValue ?? 0) U/hr from temp basal")
                    }
                } else {
                    let basalProfile = self.settingsManager.preferences.basalProfile as? [BasalProfileEntry] ?? []
                    if !basalProfile.isEmpty {
                        let now = Date()
                        let calendar = Calendar.current
                        let currentTimeMinutes = calendar.component(.hour, from: now) * 60 + calendar
                            .component(.minute, from: now)

                        var currentBasalRate: Double = 0
                        for entry in basalProfile.reversed() {
                            if entry.minutes <= currentTimeMinutes {
                                currentBasalRate = Double(entry.rate)
                                break
                            }
                        }

                        if currentBasalRate > 0 {
                            tbrValue = currentBasalRate

                            if self.debugWatchState {
                                debug(.watchManager, "⌚️ Current scheduled basal rate: \(tbrValue ?? 0) U/hr from profile")
                            }
                        }
                    }
                }

                for (index, glucose) in glucoseObjects.enumerated() {
                    var watchState = GarminSwissAlpineWatchState()

                    if let glucoseDate = glucose.date {
                        watchState.date = UInt64(glucoseDate.timeIntervalSince1970 * 1000)
                    }

                    watchState.sgv = Int16(glucose.glucose)
                    watchState.direction = glucose.direction ?? "--"

                    if index < glucoseObjects.count - 1 {
                        let deltaValue = glucose.glucose - glucoseObjects[index + 1].glucose
                        watchState.delta = Int16(deltaValue)
                    } else {
                        watchState.delta = nil
                    }

                    if index == 0 {
                        watchState.units_hint = unitsHint
                        watchState.iob = iobValue
                        watchState.cob = cobValue
                        watchState.tbr = tbrValue
                        watchState.isf = isfValue
                        watchState.eventualBG = adjustedEventualBGValue
                        watchState.sensRatio = sensRatioValue
                    }

                    watchStates.append(watchState)
                }

                if self.debugWatchState {
                    self.logSwissAlpineWatchStates(watchStates)
                }

                return watchStates
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up Garmin SwissAlpine watch state: \(error)"
            )
            throw error
        }
    }

    // MARK: - Helper Methods

    /// Formats IOB value with one decimal place.
    /// - Parameter value: The IOB decimal value to format.
    /// - Returns: A formatted string with one decimal place.
    func iobFormatterWithOneFractionDigit(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1

        if value.magnitude < 0.1, value != 0 {
            return value > 0 ? "0.1" : "-0.1"
        }

        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// Formats a Date to HH:mm:ss string for logging.
    /// - Parameter date: The date to format (defaults to current date).
    /// - Returns: A formatted time string.
    private func formatTimeForLog(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - Device & App Registration

    /// Registers the given devices for ConnectIQ events and creates watch apps for each device.
    /// - Parameter devices: The devices to register.
    private func registerDevices(_ devices: [IQDevice]) {
        watchApps.removeAll()

        for device in devices {
            connectIQ?.register(forDeviceEvents: device, delegate: self)

            let watchface = currentWatchface

            if !isWatchfaceDataDisabled {
                if let watchfaceUUID = watchface.watchfaceUUID,
                   let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
                {
                    debug(
                        .watchManager,
                        "Garmin: Registering \(watchface.displayName) watchface (UUID: \(watchfaceUUID)) for device \(device.friendlyName ?? "Unknown")"
                    )

                    watchApps.append(watchfaceApp)
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

            if let datafieldUUID = watchface.datafieldUUID,
               let watchDataFieldApp = IQApp(uuid: datafieldUUID, store: UUID(), device: device)
            {
                debug(
                    .watchManager,
                    "Garmin: Registering data field (UUID: \(datafieldUUID)) for device \(device.friendlyName ?? "Unknown")"
                )

                watchApps.append(watchDataFieldApp)
                connectIQ?.register(forAppMessages: watchDataFieldApp, delegate: self)
            } else {
                debugGarmin("Garmin: Could not create data-field app for device \(device.uuid!)")
            }
        }
    }

    /// Restores previously persisted devices from local storage.
    private func restoreDevices() {
        devices = persistedDevices.map(\.iqDevice)
    }

    // MARK: - Combine Subscriptions

    /// Subscribes to the `.openFromGarminConnect` notification for device selection.
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

    /// Subscribes to determination updates with 20-second throttling to prevent duplicate sends.
    private func subscribeToDeterminationThrottle() {
        determinationSubject
            .throttle(for: .seconds(20), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] data in
                guard let self = self else { return }

                let shouldCache: Bool
                if let lastChange = self.lastWatchfaceChangeTime {
                    let timeSinceChange = Date().timeIntervalSince(lastChange)
                    shouldCache = timeSinceChange > 25
                    if !shouldCache {
                        debugGarmin(
                            "[\(self.formatTimeForLog())] Garmin: Not caching - data may be from before watchface change (\(Int(timeSinceChange))s ago)"
                        )
                    }
                } else {
                    shouldCache = true
                }

                if shouldCache {
                    self.cachedDeterminationData = data
                }

                self.lastImmediateSendTime = Date()

                guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    debugGarmin("[\(self.formatTimeForLog())] Garmin: Invalid JSON in determination data")
                    return
                }

                debugGarmin("[\(self.formatTimeForLog())] Garmin: Sending determination/IOB (20s throttle passed)")
                self.broadcastStateToWatchApps(jsonObject as Any)
            }
            .store(in: &cancellables)
    }

    // MARK: - Parsing & Broadcasting

    /// Parses devices from a Garmin Connect URL and updates the device list.
    /// - Parameter url: The URL provided by Garmin Connect containing device selection info.
    private func parseDevices(for url: URL) {
        let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice]
        devices = parsed ?? []

        deviceSelectionPromise?(.success(devices))
        deviceSelectionPromise = nil
    }

    /// Broadcasts watch state to all registered watch apps.
    /// - Parameter state: The watch state data to broadcast.
    private func broadcastStateToWatchApps(_ state: Any) {
        if failedSendCount > 0 {
            let timeSinceLastSuccess = lastSuccessfulSendTime.map { Date().timeIntervalSince($0) } ?? .infinity
            debug(
                .watchManager,
                "[\(formatTimeForLog())] Garmin: Broadcasting with \(failedSendCount) recent failures. Last success: \(Int(timeSinceLastSuccess))s ago"
            )
        }

        watchApps.forEach { app in
            let watchface = currentWatchface
            let isWatchfaceApp = app.uuid == watchface.watchfaceUUID

            if isWatchfaceDataDisabled, isWatchfaceApp {
                debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, skipping broadcast to watchface")
                return
            }

            connectIQ?.getAppStatus(app) { [weak self] status in
                guard status?.isInstalled == true else {
                    self?.debugGarmin("[\(self?.formatTimeForLog() ?? "")] Garmin: App not installed on device: \(app.uuid!)")
                    return
                }
                debug(.watchManager, "[\(self?.formatTimeForLog() ?? "")] Garmin: Sending watch-state to app \(app.uuid!)")
                self?.sendMessage(state, to: app)
            }
        }
    }

    // MARK: - GarminManager Conformance

    /// Prompts the user to select Garmin devices.
    /// - Returns: A publisher that emits the selected devices.
    func selectDevices() -> AnyPublisher<[IQDevice], Never> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.success([]))
                return
            }
            self.deviceSelectionPromise = promise
            self.connectIQ?.showDeviceSelection()
        }
        .timeout(.seconds(120), scheduler: DispatchQueue.main)
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    /// Updates the manager's list of devices.
    /// - Parameter devices: The new array of devices to track.
    func updateDeviceList(_ devices: [IQDevice]) {
        self.devices = devices
    }

    /// Sends watch state data using 30-second throttling.
    /// - Parameter data: JSON-encoded watch state data.
    func sendWatchStateData(_ data: Data) {
        sendWatchStateDataWith30sThrottle(data)
    }

    /// Sends watch state data immediately, bypassing throttling.
    /// - Parameter data: JSON-encoded watch state data.
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

        broadcastStateToWatchApps(jsonObject)
    }

    // MARK: - Message Sending

    /// Sends a message to a given watch app.
    /// - Parameters:
    ///   - msg: The message data to send.
    ///   - app: The watch app to send to.
    private func sendMessage(_ msg: Any, to app: IQApp) {
        let watchface = currentWatchface
        let isWatchfaceApp = app.uuid == watchface.watchfaceUUID

        if isWatchfaceDataDisabled, isWatchfaceApp {
            debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, not sending message to watchface")
            return
        }

        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.failedSendCount = 0
                    self.lastSuccessfulSendTime = Date()
                    self.connectionAlertShown = false
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

                    if self.failedSendCount >= 3, !self.connectionAlertShown {
                        self.showConnectionLostAlert()
                        self.connectionAlertShown = true
                    }
                }
            }
        )
    }

    /// Shows an alert when Garmin connection is lost.
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

// MARK: - IQUIOverrideDelegate

extension BaseGarminManager: IQUIOverrideDelegate {
    /// Called if the Garmin Connect Mobile app is not installed.
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
}

// MARK: - IQDeviceEventDelegate

extension BaseGarminManager: IQDeviceEventDelegate {
    /// Called whenever a registered Garmin device status changes.
    /// - Parameters:
    ///   - device: The device whose status changed.
    ///   - status: The new device status.
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
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
}

// MARK: - IQAppMessageDelegate

extension BaseGarminManager: IQAppMessageDelegate {
    /// Called when a message is received from a Garmin watch app.
    /// - Parameters:
    ///   - message: The message content from the watch app.
    ///   - app: The watch app that sent the message.
    func receivedMessage(_ message: Any, from app: IQApp) {
        debugGarmin("[\(formatTimeForLog())] Garmin: Received message \(message) from app \(app.uuid!)")

        let watchface = currentWatchface
        let isFromWatchface = app.uuid == watchface.watchfaceUUID

        if isWatchfaceDataDisabled, isFromWatchface {
            debugGarmin("[\(formatTimeForLog())] Garmin: Watchface data disabled, ignoring message from watchface")
            return
        }

        Task {
            guard
                let statusString = message as? String,
                statusString == "status"
            else {
                return
            }

            if let lastImmediate = self.lastImmediateSendTime,
               Date().timeIntervalSince(lastImmediate) < 10
            {
                debug(
                    .watchManager,
                    "[\(self.formatTimeForLog())] Garmin: Status request ignored - just sent update \(Int(Date().timeIntervalSince(lastImmediate)))s ago"
                )
                return
            }

            do {
                if watchface == .swissalpine {
                    let watchStates = try await self.setupGarminSwissAlpineWatchState()
                    let watchStateData = try JSONEncoder().encode(watchStates)
                    self.currentSendTrigger = "Status-Request"
                    self.sendWatchStateDataWith30sThrottle(watchStateData)
                } else {
                    let watchState = try await self.setupGarminTrioWatchState()
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.currentSendTrigger = "Status-Request"
                    self.sendWatchStateDataWith30sThrottle(watchStateData)
                }
                debugGarmin("[\(self.formatTimeForLog())] Garmin: Status request queued for throttled send")
            } catch {
                debugGarmin("[\(self.formatTimeForLog())] Garmin: Cannot encode watch state: \(error)")
            }
        }
    }
}

// MARK: - SettingsObserver

extension BaseGarminManager: SettingsObserver {
    /// Called when TrioSettings change, such as units or watchface selection.
    /// - Parameter settings: The updated settings.
    func settingsDidChange(_ settings: TrioSettings) {
        debug(.watchManager, "🔔 settingsDidChange triggered")

        let watchfaceChanged = previousWatchface != settings.garminWatchface
        let dataType1Changed = previousDataType1 != settings.garminDataType1
        let dataType2Changed = previousDataType2 != settings.garminDataType2
        let unitsChanged = units != settings.units
        let disabledChanged = previousDisableWatchfaceData != settings.garminDisableWatchfaceData

        if watchfaceChanged {
            debug(
                .watchManager,
                "Garmin: Watchface changed from \(previousWatchface.displayName) to \(settings.garminWatchface.displayName). Re-registering devices only, no data update"
            )
        }

        if dataType1Changed {
            debug(
                .watchManager,
                "Garmin: Data type 1 changed from \(previousDataType1.displayName) to \(settings.garminDataType1.displayName)"
            )
        }

        if dataType2Changed {
            debug(
                .watchManager,
                "Garmin: Data type 2 changed from \(previousDataType2.displayName) to \(settings.garminDataType2.displayName)"
            )
        }

        if unitsChanged {
            debugGarmin("Garmin: Units changed - immediate update required")
        }

        if disabledChanged {
            debug(
                .watchManager,
                "Garmin: Watchface data disabled changed from \(previousDisableWatchfaceData) to \(settings.garminDisableWatchfaceData)"
            )

            registerDevices(devices)

            if settings.garminDisableWatchfaceData {
                debugGarmin("Garmin: Watchface app unregistered, datafield continues")
            } else {
                debugGarmin("Garmin: Watchface app re-registered - sending immediate update")
            }
        }

        units = settings.units
        previousWatchface = settings.garminWatchface
        previousDataType1 = settings.garminDataType1
        previousDataType2 = settings.garminDataType2
        previousDisableWatchfaceData = settings.garminDisableWatchfaceData

        if watchfaceChanged {
            cachedDeterminationData = nil
            lastWatchfaceChangeTime = Date()
            debugGarmin("Garmin: Cleared cached determination data due to watchface change")

            registerDevices(devices)
            debugGarmin("Garmin: Re-registered devices for new watchface UUID")
        }

        let needsImmediateUpdate = (
            unitsChanged ||
                (disabledChanged && !settings.garminDisableWatchfaceData)
        ) &&
            !watchfaceChanged

        let needsThrottledUpdate = (dataType1Changed || dataType2Changed) &&
            !watchfaceChanged

        if needsImmediateUpdate {
            Task {
                do {
                    if let cachedData = self.cachedDeterminationData {
                        self.currentSendTrigger = "Settings-Units/Re-enable"
                        debugGarmin("Garmin: Using cached determination data for immediate settings update")
                        self.sendWatchStateDataImmediately(cachedData)
                        self.lastImmediateSendTime = Date()
                        debugGarmin("Garmin: Immediate update sent for units/re-enable change (from cache)")
                    } else {
                        if settings.garminWatchface == .swissalpine {
                            let watchStates = try await self.setupGarminSwissAlpineWatchState()
                            let watchStateData = try JSONEncoder().encode(watchStates)
                            self.currentSendTrigger = "Settings-Units/Re-enable"
                            self.sendWatchStateDataImmediately(watchStateData)
                            self.lastImmediateSendTime = Date()
                            debugGarmin("Garmin: Immediate update sent for units/re-enable change (fresh query)")
                        } else {
                            let watchState = try await self.setupGarminTrioWatchState()
                            let watchStateData = try JSONEncoder().encode(watchState)
                            self.currentSendTrigger = "Settings-Units/Re-enable"
                            self.sendWatchStateDataImmediately(watchStateData)
                            self.lastImmediateSendTime = Date()
                            debugGarmin("Garmin: Immediate update sent for units/re-enable change (fresh query)")
                        }
                    }
                } catch {
                    debug(
                        .watchManager,
                        "\(DebuggingIdentifiers.failed) Failed to send immediate update after settings change: \(error)"
                    )
                }
            }
        } else if needsThrottledUpdate {
            Task {
                do {
                    if settings.garminWatchface == .swissalpine {
                        let watchStates = try await self.setupGarminSwissAlpineWatchState()
                        let watchStateData = try JSONEncoder().encode(watchStates)
                        self.currentSendTrigger = "Settings-DataType"
                        self.sendWatchStateDataWith30sThrottle(watchStateData)
                        debugGarmin("Garmin: Throttled update queued for data type change")
                    } else {
                        let watchState = try await self.setupGarminTrioWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.currentSendTrigger = "Settings-DataType"
                        self.sendWatchStateDataWith30sThrottle(watchStateData)
                        debugGarmin("Garmin: Throttled update queued for data type change")
                    }
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
