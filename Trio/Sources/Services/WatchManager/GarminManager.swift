import Combine
import ConnectIQ
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

    @Injected() private var iobService: IOBService!

    /// LiveActivityManager provides a reliable data snapshot (glucose, determination, IOB)
    /// that has already been fetched from CoreData via a long-lived, auto-merging context.
    @Injected() private var liveActivityManager: LiveActivityManager!

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

    /// Queue for serializing watch state updates.
    private let queue = DispatchQueue(label: "BaseGarminManager.queue", qos: .utility)

    /// Subscriptions for LiveActivity snapshot, periodic refresh, and other Combine pipelines.
    private var subscriptions = Set<AnyCancellable>()

    /// Tracks the last time a message was successfully sent to any watch app.
    /// Used for health monitoring — if sends are failing silently, the periodic refresh
    /// timer can detect and log the gap.
    private var lastSuccessfulSend: Date?

    /// Counts consecutive send failures across all watch apps. Reset on any successful send.
    private var consecutiveSendFailures: Int = 0

    /// Tracks watch apps that have a sendMessage call in-flight (not yet completed).
    /// If an app's UUID is in this set, new sends to that app are skipped to prevent
    /// saturating the GCM BLE transfer queue. The next cycle will send fresh data.
    private var appsWithInFlightSend: Set<UUID> = []

    /// The most recent encoded watch-state JSON data, cached for resending on poll requests
    /// and periodic refresh without re-fetching from CoreData.
    private var lastWatchStateData: Data?

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

        subscribeToUpdateTriggers()
        subscribeToPeriodicRefresh()
    }

    // MARK: - Internal Setup / Handlers

    /// Subscribes to LiveActivityManager's snapshot publisher to receive the same reliable
    /// glucose/determination/IOB data that feeds the Live Activity. This eliminates the
    /// stale-data problem caused by NSBatchInsertRequest bypassing CoreData's change
    /// propagation — the Live Activity's long-lived context auto-merges save notifications
    /// and always has fresh data.
    private func subscribeToUpdateTriggers() {
        liveActivityManager.snapshotPublisher
            .receive(on: queue)
            .sink { [weak self] snapshot in
                guard let self = self else { return }
                guard !self.devices.isEmpty else { return }

                let timeFmt = DateFormatter()
                timeFmt.dateFormat = "HH:mm:ss"
                debug(
                    .watchManager,
                    "Garmin: LiveActivity snapshot received - glucose: \(snapshot.glucose.glucose) @ \(timeFmt.string(from: snapshot.glucose.date))"
                )

                let watchState = self.buildWatchState(from: snapshot)
                do {
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.lastWatchStateData = watchStateData
                    self.sendWatchStateData(watchStateData)
                } catch {
                    debug(
                        .watchManager,
                        "\(DebuggingIdentifiers.failed) Error encoding watch state: \(error)"
                    )
                }
            }
            .store(in: &subscriptions)
    }

    /// Builds a GarminWatchState from a LiveActivitySnapshot — no CoreData fetch required.
    /// Uses the same data that the Live Activity displays, which is always fresh.
    private func buildWatchState(from snapshot: LiveActivitySnapshot) -> GarminWatchState {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"

        var watchState = GarminWatchState()

        // IOB — use the snapshot value (same source as Live Activity)
        let iobValue = snapshot.iob ?? iobService.currentIOB ?? 0
        watchState.iob = iobFormatterWithOneFractionDigit(iobValue)

        // Determination data (COB, last loop date, ISF, eventualBG)
        if let determination = snapshot.determination {
            if let date = determination.date {
                watchState.lastLoopDateInterval = date.timeIntervalSince1970 > 0
                    ? UInt64(date.timeIntervalSince1970) : 0
            }

            let cobNumber = NSNumber(value: determination.cob)
            watchState.cob = Formatter.integerFormatter.string(from: cobNumber)

            let insulinSensitivity = determination.insulinSensitivity ?? 0
            let eventualBG = determination.eventualBG ?? 0

            if units == .mgdL {
                watchState.isf = insulinSensitivity == 0 ? nil : insulinSensitivity.description
                watchState.eventualBGRaw = eventualBG == 0 ? nil : eventualBG.description
            } else {
                if insulinSensitivity != 0 {
                    watchState.isf = Double(truncating: insulinSensitivity as NSNumber).asMmolL.description
                }
                if eventualBG != 0 {
                    watchState.eventualBGRaw = Double(truncating: eventualBG as NSNumber).asMmolL.description
                }
            }
        }

        // Glucose
        let bg = snapshot.glucose
        if units == .mgdL {
            watchState.glucose = "\(bg.glucose)"
        } else {
            let mgdlValue = Decimal(bg.glucose)
            watchState.glucose = "\(Double(truncating: mgdlValue.asMmolL as NSNumber))"
        }

        // Glucose timestamp diagnostic
        watchState.glucoseDate = timeFmt.string(from: bg.date)

        // Trend
        watchState.trendRaw = bg.direction?.rawValue ?? "--"

        // Delta
        if let prev = snapshot.previousGlucose {
            var deltaValue = Decimal(bg.glucose - prev.glucose)
            if units == .mmolL {
                deltaValue = Double(truncating: deltaValue as NSNumber).asMmolL
            }
            let formattedDelta = deltaValue.description
            watchState.delta = deltaValue < 0 ? "\(formattedDelta)" : "+\(formattedDelta)"
        }

        // Diagnostic: when the phone built this payload
        watchState.sentAt = timeFmt.string(from: Date())
        // Diagnostic: delivery path (overridden to "poll" in receivedMessage)
        watchState.source = "push"

        debug(
            .watchManager,
            """
            📱 Setup GarminWatchState (from LiveActivity snapshot) - \
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
    /// to match the ~5-minute CGM reading interval. ConnectIQ watch faces use a one-shot
    /// registerForPhoneAppMessageEvent model — each delivery requires a full background service
    /// cycle (wake → process → exit → re-register) taking 10-30 seconds. A 10-second throttle
    /// produced ~6 messages/minute while the watch could only consume ~2-3/minute, causing an
    /// unbounded queue and 30+ minute delay. At 300 seconds, one proactive push per CGM cycle
    /// keeps the queue shallow. The watch's 5-minute poll ("status") bypasses this throttle for
    /// immediate responses (see receivedMessage(_:from:)).
    private func subscribeToWatchState() {
        watchStateSubject
            .throttle(for: .seconds(300), scheduler: DispatchQueue.main, latest: true)
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
                guard let data = self.lastWatchStateData else {
                    debug(.watchManager, "Garmin: Periodic refresh - no cached state yet, skipping")
                    return
                }
                debug(.watchManager, "Garmin: Periodic refresh - resending last watch state")
                self.sendWatchStateData(data)
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

    /// Sends a message to a given IQApp, gated by in-flight tracking to prevent queue saturation.
    /// If a previous send to this app hasn't completed yet, the new send is skipped entirely —
    /// the next loop cycle (5 minutes) will send fresh data, so nothing is lost.
    /// - Parameters:
    ///   - msg: The dictionary to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    private func sendMessage(_ msg: NSDictionary, to app: IQApp) {
        let appUUID = app.uuid!

        guard !appsWithInFlightSend.contains(appUUID) else {
            debug(.watchManager, "Garmin: Skipping send to \(appUUID) — previous send still in-flight")
            return
        }

        appsWithInFlightSend.insert(appUUID)

        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in },
            completion: { [weak self] result in
                self?.appsWithInFlightSend.remove(appUUID)

                switch result {
                case .success:
                    self?.lastSuccessfulSend = Date()
                    self?.consecutiveSendFailures = 0
                    debug(.watchManager, "Garmin: Successfully sent message to \(appUUID)")
                default:
                    let failures = (self?.consecutiveSendFailures ?? 0) + 1
                    self?.consecutiveSendFailures = failures
                    let lastSendAgo = self?.lastSuccessfulSend.map { "\(Int(-$0.timeIntervalSinceNow))s ago" } ?? "never"
                    debug(
                        .watchManager,
                        "Garmin: Failed to send message to \(appUUID) " +
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
    /// If the watch requests a "status" update, we immediately respond with the cached watch state.
    /// - Parameters:
    ///   - message: The message content from the watch app.
    ///   - app: The watch app sending the message.
    func receivedMessage(_ message: Any, from app: IQApp) {
        debug(.watchManager, "Garmin: Received message \(message) from app \(app.uuid!)")

        // Check if the message is literally the string "status"
        guard
            let statusString = message as? String,
            statusString == "status"
        else {
            return
        }

        guard let watchStateData = lastWatchStateData else {
            debug(.watchManager, "Garmin: Poll response - no cached state yet")
            return
        }

        // Bypass the throttle for poll responses — the watch is actively waiting
        // for a reply and its background service may go back to sleep if we delay.
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: watchStateData, options: .mutableContainers),
            let dict = jsonObject as? NSMutableDictionary
        else {
            debug(.watchManager, "Garmin: Invalid JSON for poll response")
            return
        }
        // Override source so the watch can distinguish poll responses from proactive pushes
        dict["source"] = "poll"
        broadcastStateToWatchApps(dict)
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
        // Update local units — the next LiveActivity snapshot will rebuild with the new units
        units = settingsManager.settings.units

        // Resend cached state if available (it will use the previous units, but the next
        // LiveActivity snapshot will arrive shortly with the correct units)
        if let data = lastWatchStateData {
            sendWatchStateData(data)
        }
    }
}
