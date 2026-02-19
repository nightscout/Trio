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
///  - Generating & sending watch-state updates (glucose, IOB, COB, etc.) to Garmin watch apps.
final class BaseGarminManager: NSObject, GarminManager, Injectable {
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

    /// A subject that publishes watch-state dictionaries; watchers can throttle or debounce.
    private let watchStateSubject = PassthroughSubject<NSDictionary, Never>()

    /// A set of Combine cancellables for managing the lifecycle of various subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Holds a promise used when the user is selecting devices (via `showDeviceSelection()`).
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

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

    /// Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseGarminManager.queue", qos: .utility)

    /// Publishes any changed CoreData objects that match our filters (e.g., OrefDetermination, GlucoseStored).
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?

    /// Additional local subscriptions (separate from `cancellables`) for CoreData events.
    private var subscriptions = Set<AnyCancellable>()

    /// Represents the main (view) context for CoreData, typically used on the main thread.
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    /// Tracks the last time a message was successfully sent to any watch app.
    /// Used for health monitoring — if sends are failing silently, the periodic refresh
    /// timer can detect and log the gap.
    private var lastSuccessfulSend: Date?

    /// Counts consecutive send failures across all watch apps. Reset on any successful send.
    private var consecutiveSendFailures: Int = 0

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
        subscribeToOpenFromGarminConnect()
        subscribeToWatchState()

        units = settingsManager.settings.units

        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        subscribeToUpdateTriggers()
        subscribeToPeriodicRefresh()
        registerHandlers()
    }

    // MARK: - Internal Setup / Handlers

    /// Merges all data-change triggers into a single debounced pipeline.
    ///
    /// Previously, four independent subscribers each called `setupGarminWatchState()` immediately
    /// on their own trigger. When multiple triggers fired near-simultaneously (e.g., OrefDetermination
    /// save + IOB update + glucose batch insert), up to 4 concurrent Tasks would race to build
    /// the watch state. The throttle's `latest: true` emitted the FIRST value immediately — which
    /// often carried stale glucose because the OrefDetermination trigger fires before the new
    /// glucose batch insert completes.
    ///
    /// By merging all triggers and debouncing for 500ms, we wait for all data to settle before
    /// building the watch state exactly once. This eliminates the race condition and reduces
    /// unnecessary CoreData contention.
    private func subscribeToUpdateTriggers() {
        let glucoseTrigger = glucoseStorage.updatePublisher
            .map { _ in "glucose" }
            .eraseToAnyPublisher()

        let iobTrigger = iobService.iobPublisher
            .map { _ in "iob" }
            .eraseToAnyPublisher()

        let determinationTrigger = coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .map { _ in "determination" }
            .eraseToAnyPublisher() ?? Empty<String, Never>().eraseToAnyPublisher()

        // Due to the batch insert, this only observes deletion of Glucose entries
        let glucoseDeleteTrigger = coreDataPublisher?
            .filteredByEntityName("GlucoseStored")
            .map { _ in "glucoseDelete" }
            .eraseToAnyPublisher() ?? Empty<String, Never>().eraseToAnyPublisher()

        Publishers.Merge4(glucoseTrigger, iobTrigger, determinationTrigger, glucoseDeleteTrigger)
            .receive(on: queue)
            .debounce(for: .milliseconds(500), scheduler: queue)
            .sink { [weak self] trigger in
                guard let self = self else { return }
                guard !self.devices.isEmpty else { return }
                debug(.watchManager, "Garmin: Debounced update triggered by: \(trigger)")
                Task {
                    do {
                        let watchState = try await self.setupGarminWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.sendWatchStateData(watchStateData)
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

    /// Registers additional CoreData-based handlers that aren't covered by the merged pipeline.
    /// Currently empty — all handlers have been merged into `subscribeToUpdateTriggers()`.
    /// Retained as extension point for future entity-specific handlers.
    private func registerHandlers() {
        // All handlers are now consolidated in subscribeToUpdateTriggers()
    }

    /// Fetches recent glucose readings from CoreData, up to 288 results.
    /// - Parameter context: The managed object context to fetch on.
    /// - Returns: An array of `NSManagedObjectID`s for glucose readings.
    private func fetchGlucose(on context: NSManagedObjectContext) async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Builds a `GarminWatchState` reflecting the latest glucose, trend, delta, eventual BG, ISF, IOB, and COB.
    /// - Returns: A `GarminWatchState` containing the most recent device- and therapy-related info.
    func setupGarminWatchState() async throws -> GarminWatchState {
        // Skip expensive calculations if no Garmin devices are connected
        guard !devices.isEmpty else {
            debug(.watchManager, "⌚️❌ Skipping setupGarminWatchState - No Garmin devices connected")
            return GarminWatchState()
        }
        do {
            // Use a fresh context for every call. A brand-new context has zero row cache,
            // so it must fetch from the persistent store. This eliminates stale reads caused
            // by NSBatchInsertRequest writing directly to SQLite and bypassing Core Data's
            // change-propagation mechanism (the previous backgroundContext.reset() approach
            // only cleared the context cache, not the PSC row cache).
            let freshContext = CoreDataStack.shared.newTaskContext()

            // Get Glucose IDs
            let glucoseIds = try await fetchGlucose(on: freshContext)

            // Fetch the latest OrefDetermination object if available
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.predicateFor30MinAgoForDetermination
            )

            // Turn those IDs into live NSManagedObjects
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: freshContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: freshContext)

            // Perform logic on the fresh context
            return await freshContext.perform {
                let timeFmt = DateFormatter()
                timeFmt.dateFormat = "HH:mm:ss"

                // Log fetch results for diagnostics — helps distinguish stale-fetch vs queued-message
                debug(
                    .watchManager,
                    """
                    📱 Garmin fetch results - \
                    freshContext: \(freshContext.name ?? freshContext.description), \
                    glucoseCount: \(glucoseObjects.count), \
                    latestGlucoseValue: \(glucoseObjects.first.map { "\($0.glucose)" } ?? "none"), \
                    latestGlucoseDate: \(glucoseObjects.first?.date.map { timeFmt.string(from: $0) } ?? "nil"), \
                    determinationCount: \(determinationObjects.count)
                    """
                )

                var watchState = GarminWatchState()

                /// Pull `glucose`, `trendRaw`, `delta`, `lastLoopDateInterval`, `iob`, `cob`,  `isf`, and `eventualBGRaw` from the latest determination.
                let iobValue = self.iobService.currentIOB ?? 0
                watchState.iob = self.iobFormatterWithOneFractionDigit(iobValue)

                if let latestDetermination = determinationObjects.first {
                    watchState.lastLoopDateInterval = latestDetermination.timestamp.map {
                        guard $0.timeIntervalSince1970 > 0 else { return 0 }
                        return UInt64($0.timeIntervalSince1970)
                    }

                    let cobNumber = NSNumber(value: latestDetermination.cob)
                    watchState.cob = Formatter.integerFormatter.string(from: cobNumber)

                    let insulinSensitivity = latestDetermination.insulinSensitivity ?? 0
                    let eventualBG = latestDetermination.eventualBG ?? 0

                    if self.units == .mgdL {
                        watchState.isf = insulinSensitivity.description
                        watchState.eventualBGRaw = eventualBG.description
                    } else {
                        let parsedIsf = Double(truncating: insulinSensitivity).asMmolL
                        let parsedEventualBG = Double(truncating: eventualBG).asMmolL

                        watchState.isf = parsedIsf.description
                        watchState.eventualBGRaw = parsedEventualBG.description
                    }
                }

                // If no glucose data is present, just return partial watch state
                guard let latestGlucose = glucoseObjects.first else {
                    watchState.sentAt = timeFmt.string(from: Date())
                    return watchState
                }

                // Format the current glucose reading
                if self.units == .mgdL {
                    watchState.glucose = "\(latestGlucose.glucose)"
                } else {
                    let mgdlValue = Decimal(latestGlucose.glucose)
                    let latestGlucoseValue = Double(truncating: mgdlValue.asMmolL as NSNumber)
                    watchState.glucose = "\(latestGlucoseValue)"
                }

                // Diagnostic: timestamp of the glucose reading for watch debug face.
                // Always set a non-nil value so it appears in the JSON (JSONEncoder encodes
                // nil optionals as null which ConnectIQ may silently drop).
                if let glucoseTimestamp = latestGlucose.date {
                    watchState.glucoseDate = timeFmt.string(from: glucoseTimestamp)
                } else {
                    watchState.glucoseDate = "no-date"
                }

                // Convert direction to a textual trend
                watchState.trendRaw = latestGlucose.direction ?? "--"

                // Calculate a glucose delta if we have at least two readings
                if glucoseObjects.count >= 2 {
                    var deltaValue = Decimal(glucoseObjects[0].glucose - glucoseObjects[1].glucose)

                    if self.units == .mmolL {
                        deltaValue = Double(truncating: deltaValue as NSNumber).asMmolL
                    }

                    let formattedDelta = deltaValue.description
                    watchState.delta = deltaValue < 0 ? "\(formattedDelta)" : "+\(formattedDelta)"
                }

                // Diagnostic: when the phone built this payload (distinguishes stale fetch
                // from ConnectIQ message queuing delay).
                watchState.sentAt = timeFmt.string(from: Date())

                debug(
                    .watchManager,
                    """
                    📱 Setup GarminWatchState - \
                    glucose: \(watchState.glucose ?? "nil"), \
                    glucoseDate: \(watchState.glucoseDate ?? "nil"), \
                    sentAt: \(watchState.sentAt ?? "nil"), \
                    trendRaw: \(watchState.trendRaw ?? "nil"), \
                    delta: \(watchState.delta ?? "nil"), \
                    eventualBGRaw: \(watchState.eventualBGRaw ?? "nil"), \
                    isf: \(watchState.isf ?? "nil"), \
                    cob: \(watchState.cob ?? "nil"), \
                    iob: \(watchState.iob ?? "nil"), \
                    lastLoopDateInterval: \(watchState.lastLoopDateInterval?.description ?? "nil")
                    """
                )

                return watchState
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up Garmin watch state: \(error)"
            )
            throw error
        }
    }

    // MARK: - Device & App Registration

    /// Registers the given devices for ConnectIQ events (device status changes) and watch app messages.
    /// It also creates and registers watch apps (watchface + data field) for each device.
    /// - Parameter devices: The devices to register.
    private func registerDevices(_ devices: [IQDevice]) {
        // Clear out old references
        watchApps.removeAll()

        for device in devices {
            // Listen for device-level status changes
            connectIQ?.register(forDeviceEvents: device, delegate: self)

            // Create a watchface app
            guard
                let watchfaceUUID = Config.watchfaceUUID,
                let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
            else {
                debug(.watchManager, "Garmin: Could not create watchface app for device \(device.uuid!))")
                continue
            }

            // Create a watch data field app
            guard
                let watchdataUUID = Config.watchdataUUID,
                let watchDataFieldApp = IQApp(uuid: watchdataUUID, store: UUID(), device: device)
            else {
                debug(.watchManager, "Garmin: Could not create data-field app for device \(device.uuid!)")
                continue
            }

            // Track both apps for potential messages
            watchApps.append(watchfaceApp)
            watchApps.append(watchDataFieldApp)

            // Register to receive app-messages from the watchface
            connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
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

    /// Subscribes to any watch-state dictionaries published via `watchStateSubject`, and throttles them
    /// so updates aren't sent too frequently. Each update triggers a broadcast to all watch apps.
    private func subscribeToWatchState() {
        watchStateSubject
            .throttle(for: .seconds(10), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] state in
                self?.broadcastStateToWatchApps(state)
            }
            .store(in: &cancellables)
    }

    /// Unconditional 5-minute periodic refresh as a safety net.
    ///
    /// If the event-driven Combine pipeline silently dies (e.g., ConnectIQ SDK enters a bad state,
    /// iOS kills the Garmin Connect Mobile bridge, or a Combine subscription gets garbage collected),
    /// this timer ensures data still flows to the watch. It fires unconditionally — no reset on
    /// successful event-driven sends — because simplicity and reliability matter more than avoiding
    /// a few redundant sends. The output throttle on `watchStateSubject` deduplicates if an
    /// event-driven update just went through.
    private func subscribeToPeriodicRefresh() {
        Timer.publish(every: 5 * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard !self.devices.isEmpty else { return }
                debug(.watchManager, "Garmin: Periodic refresh timer fired")
                Task {
                    do {
                        let watchState = try await self.setupGarminWatchState()
                        let watchStateData = try JSONEncoder().encode(watchState)
                        self.sendWatchStateData(watchStateData)
                    } catch {
                        debug(
                            .watchManager,
                            "\(DebuggingIdentifiers.failed) Error in periodic refresh: \(error)"
                        )
                    }
                }
            }
            .store(in: &subscriptions)
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

    /// Sends the given state dictionary to all known watch apps (watchface & data field) by checking
    /// if each app is installed and then sending messages asynchronously.
    /// - Parameter state: The dictionary representing the watch state to be broadcast.
    private func broadcastStateToWatchApps(_ state: NSDictionary) {
        watchApps.forEach { app in
            connectIQ?.getAppStatus(app) { [weak self] status in
                guard status?.isInstalled == true else {
                    debug(.watchManager, "Garmin: App not installed on device: \(app.uuid!)")
                    return
                }
                debug(.watchManager, "Garmin: Sending watch-state to app \(app.uuid!)")
                self?.sendMessage(state, to: app)
            }
        }
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
    /// - Parameter data: JSON-encoded data representing the latest watch state. If decoding fails,
    ///   the method logs an error and does nothing else.
    func sendWatchStateData(_ data: Data) {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = jsonObject as? NSDictionary
        else {
            debug(.watchManager, "Garmin: Invalid JSON for watch-state data")
            return
        }
        watchStateSubject.send(dict)
    }

    // MARK: - Helper: Sending Messages

    /// Sends a message to a given IQApp with optional progress and completion callbacks.
    /// Tracks success/failure for health monitoring.
    /// - Parameters:
    ///   - msg: The dictionary to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    private func sendMessage(_ msg: NSDictionary, to app: IQApp) {
        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in },
            completion: { [weak self] result in
                switch result {
                case .success:
                    self?.lastSuccessfulSend = Date()
                    self?.consecutiveSendFailures = 0
                    debug(.watchManager, "Garmin: Successfully sent message to \(app.uuid!)")
                default:
                    let failures = (self?.consecutiveSendFailures ?? 0) + 1
                    self?.consecutiveSendFailures = failures
                    let lastSendAgo = self?.lastSuccessfulSend.map { "\(Int(-$0.timeIntervalSinceNow))s ago" } ?? "never"
                    debug(
                        .watchManager,
                        "Garmin: Failed to send message to \(app.uuid!) " +
                            "(consecutive failures: \(failures), last success: \(lastSendAgo))"
                    )
                }
            }
        )
    }

    func iobFormatterWithOneFractionDigit(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1

        // Prevent small values from rounding to 0 by enforcing a minimum threshold
        if value.magnitude < 0.1, value != 0 {
            return value > 0 ? "0.1" : "-0.1"
        }

        return formatter.string(from: value as NSNumber) ?? "\(value)"
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
        switch status {
        case .invalidDevice:
            debug(.watchManager, "Garmin: invalidDevice (\(device.uuid!))")
        case .bluetoothNotReady:
            debug(.watchManager, "Garmin: bluetoothNotReady (\(device.uuid!))")
        case .notFound:
            debug(.watchManager, "Garmin: notFound (\(device.uuid!))")
        case .notConnected:
            debug(.watchManager, "Garmin: notConnected (\(device.uuid!))")
        case .connected:
            debug(.watchManager, "Garmin: connected (\(device.uuid!))")
        @unknown default:
            debug(.watchManager, "Garmin: unknown state (\(device.uuid!))")
        }
    }

    // MARK: - IQAppMessageDelegate

    /// Called when a message arrives from a Garmin watch app (watchface or data field).
    /// If the watch requests a "status" update, we call `setupGarminWatchState()` asynchronously
    /// and re-send the watch state data.
    /// - Parameters:
    ///   - message: The message content from the watch app.
    ///   - app: The watch app sending the message.
    func receivedMessage(_ message: Any, from app: IQApp) {
        debug(.watchManager, "Garmin: Received message \(message) from app \(app.uuid!)")

        Task {
            // Check if the message is literally the string "status"
            guard
                let statusString = message as? String,
                statusString == "status"
            else {
                return
            }

            do {
                // Fetch the latest watch state (async) and encode it to JSON data
                let watchState = try await self.setupGarminWatchState()
                let watchStateData = try JSONEncoder().encode(watchState)

                // Bypass the throttle for poll responses — the watch is actively waiting
                // for a reply and its background service may go back to sleep if we delay.
                guard
                    let jsonObject = try? JSONSerialization.jsonObject(with: watchStateData, options: []),
                    let dict = jsonObject as? NSDictionary
                else {
                    debug(.watchManager, "Garmin: Invalid JSON for poll response")
                    return
                }
                await MainActor.run {
                    self.broadcastStateToWatchApps(dict)
                }
            } catch {
                debug(.watchManager, "Garmin: Cannot encode watch state: \(error)")
            }
        }
    }
}

extension BaseGarminManager {
    // MARK: - Config

    /// Configuration struct containing watch app UUIDs for the Garmin watchface and data field.
    private enum Config {
        static let watchfaceUUID = UUID(uuidString: "88553264-FE3D-42FA-A9E6-72A0A9D2A5D3")
        static let watchdataUUID = UUID(uuidString: "C8B7A6F5-E4D3-4C2B-A190-F6E5D4C3B2A1")
    }
}

extension BaseGarminManager: SettingsObserver {
    /// Called whenever TrioSettings changes (e.g., user toggles mg/dL vs. mmol/L).
    /// - Parameter _: The updated TrioSettings instance.
    func settingsDidChange(_: TrioSettings) {
        // Update local units and re-send watch state
        units = settingsManager.settings.units

        Task {
            do {
                let watchState = try await setupGarminWatchState()
                let watchStateData = try JSONEncoder().encode(watchState)
                sendWatchStateData(watchStateData)
            } catch {
                debug(
                    .watchManager,
                    "\(DebuggingIdentifiers.failed) failed to send watch state data: \(error)"
                )
            }
        }
    }
}
