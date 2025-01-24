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

    /// An async closure that, when called, returns the latest watch state data (encoded as `Data`)
    /// to be sent to the watch on demand (e.g., when the watch pings "status").
    var watchStateDataProvider: (() async -> Data)? { get set }
}

// MARK: - BaseGarminManager

/// Concrete implementation of `GarminManager` that handles device registration, data persistence,
/// and sending watch-state updates via the Garmin ConnectIQ SDK.
final class BaseGarminManager: NSObject, GarminManager, Injectable {
    // MARK: - Config

    private enum Config {
        /// Example watchface UUID
        static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")
        /// Example data field UUID
        static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
    }

    // MARK: - Dependencies & Properties

    /// NotificationCenter used for responding to `.openFromGarminConnect` notifications.
    @Injected() private var notificationCenter: NotificationCenter!
    @Injected() private var watchManager: WatchManager!

    /// Persists the user’s device list between app launches.
    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    /// Router for presenting alerts or navigation flows (injected via Swinject).
    private let router: Router

    /// Garmin ConnectIQ shared instance for all watch interactions.
    private let connectIQ = ConnectIQ.sharedInstance()

    /// Keeps references to watch apps (both watchface & data field) for each registered device.
    private var watchApps: [IQApp] = []

    /// A subject that dispatches watch-state dictionaries to the watch on a throttled schedule.
    private let watchStateSubject = PassthroughSubject<NSDictionary, Never>()

    /// A set of Combine cancellables for managing the lifecycle of various subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Holds a promise used when the user is selecting devices (via `showDeviceSelection()`).
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

    /// Async closure returning JSON-encoded watch state. Called when the watch pings "status".
    var watchStateDataProvider: (() async -> Data)?

    /// Array of Garmin `IQDevice` objects currently being tracked.
    /// Changing this property triggers re-registration and updates persisted devices.
    private(set) var devices: [IQDevice] = [] {
        didSet {
            // Persist newly updated device list
            persistedDevices = devices.map(GarminDevice.init)
            // Re-register for events, app messages, etc.
            registerDevices(devices)
        }
    }

    // MARK: - Initialization

    /// Creates a new `BaseGarminManager`, injecting required services and restoring any persisted devices.
    /// - Parameter resolver: Swinject resolver for injecting dependencies like the Router.
    init(resolver: Resolver) {
        router = resolver.resolve(Router.self)!
        super.init()

        // Initialize ConnectIQ with a custom URL scheme and override delegate
        connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)

        // Inject any property wrappers that need the resolver
        injectServices(resolver)

        // Restore previously persisted devices
        restoreDevices()

        // Subscribe to relevant notifications and watch-state changes
        subscribeToOpenFromGarminConnect()
        subscribeToWatchState()
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
                debug(.watchManager, "Garmin: Could not create watchface app for device \(String(describing: device.uuid))")
                continue
            }

            // Create a watch data field app
            guard
                let watchdataUUID = Config.watchdataUUID,
                let watchDataFieldApp = IQApp(uuid: watchdataUUID, store: UUID(), device: device)
            else {
                debug(.watchManager, "Garmin: Could not create data-field app for device \(String(describing: device.uuid))")
                continue
            }

            // Track both apps for potential messages
            watchApps.append(watchfaceApp)
            watchApps.append(watchDataFieldApp)

            // Register to receive app-messages from the watchface (if you also want data-field messages,
            // register that, too)
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
    /// so updates aren’t sent too frequently. Each update triggers a broadcast to all watch apps.
    private func subscribeToWatchState() {
        watchStateSubject
            .throttle(for: .seconds(10), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] state in
                self?.broadcastStateToWatchApps(state)
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

    /// Sends the given state dictionary to all known watch apps (watchface & data field) by checking
    /// if each app is installed and then sending messages asynchronously.
    /// - Parameter state: The dictionary representing the watch state to be broadcast.
    private func broadcastStateToWatchApps(_ state: NSDictionary) {
        watchApps.forEach { app in
            connectIQ?.getAppStatus(app) { [weak self] status in
                guard status?.isInstalled == true else {
                    debug(.watchManager, "Garmin: App not installed on device: \(String(describing: app.uuid))")
                    return
                }
                debug(.watchManager, "Garmin: Sending watch-state to app \(String(describing: app.uuid))")
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

    /// Updates the manager’s list of devices, typically after user selection or manual changes.
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
    /// - Parameters:
    ///   - msg: The dictionary to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    private func sendMessage(_ msg: NSDictionary, to app: IQApp) {
        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in
                // Optionally track progress here
            },
            completion: { result in
                switch result {
                case .success:
                    debug(.watchManager, "Garmin: Successfully sent message to \(String(describing: app.uuid))")
                default:
                    debug(.watchManager, "Garmin: Unknown result or failed to send message to \(String(describing: app.uuid))")
                }
            }
        )
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
            debug(.watchManager, "Garmin: invalidDevice (\(String(describing: device.uuid)))")
        case .bluetoothNotReady:
            debug(.watchManager, "Garmin: bluetoothNotReady (\(String(describing: device.uuid)))")
        case .notFound:
            debug(.watchManager, "Garmin: notFound (\(String(describing: device.uuid)))")
        case .notConnected:
            debug(.watchManager, "Garmin: notConnected (\(String(describing: device.uuid)))")
        case .connected:
            debug(.watchManager, "Garmin: connected (\(String(describing: device.uuid)))")
        @unknown default:
            debug(.watchManager, "Garmin: unknown state (\(String(describing: device.uuid)))")
        }
    }

    // MARK: - IQAppMessageDelegate

    /// Called when a message arrives from a Garmin watch app (watchface or data field).
    /// If the watch requests a "status" update, we call `setupWatchState()` asynchronously
    /// and re-send the watch state data.
    func receivedMessage(_ message: Any, from app: IQApp) {
        debug(.watchManager, "Garmin: Received message \(message) from app \(String(describing: app.uuid))")

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
                let watchState = await watchManager.setupWatchState()
                let watchStateData = try JSONEncoder().encode(watchState)

                // Now send that JSON to the watch
                sendWatchStateData(watchStateData)
            } catch {
                warning(.service, "Garmin: Cannot encode watch state: \(error)")
            }
        }
    }
}
