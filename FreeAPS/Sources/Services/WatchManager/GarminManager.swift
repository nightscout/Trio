import Combine
import ConnectIQ
import Foundation
import Swinject

protocol GarminManager {
    func selectDevices() -> AnyPublisher<[IQDevice], Never>
    func updateListDevices(devices: [IQDevice])
    var devices: [IQDevice] { get }
    func sendState(_ data: Data)
    var stateRequet: (() -> (Data))? { get set }
}

extension Notification.Name {
    static let openFromGarminConnect = Notification.Name("Notification.Name.openFromGarminConnect")
}

final class BaseGarminManager: NSObject, GarminManager, Injectable {
    private enum Config {
        static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")
        static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
    }

    private let connectIQ = ConnectIQ.sharedInstance()

    private let router = FreeAPSApp.resolver.resolve(Router.self)!

    @Injected() private var notificationCenter: NotificationCenter!

    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [CodableDevice] = []

    private var watchfaces: [IQApp] = []

    var stateRequet: (() -> (Data))?

    private let stateSubject = PassthroughSubject<NSDictionary, Never>()

    private(set) var devices: [IQDevice] = [] {
        didSet {
            persistedDevices = devices.map(CodableDevice.init)
            watchfaces = []
            devices.forEach { device in
                connectIQ?.register(forDeviceEvents: device, delegate: self)
                let watchfaceApp = IQApp(
                    uuid: Config.watchfaceUUID,
                    store: UUID(),
                    device: device
                )
                let watchDataFieldApp = IQApp(
                    uuid: Config.watchdataUUID,
                    store: UUID(),
                    device: device
                )
                watchfaces.append(watchfaceApp!)
                watchfaces.append(watchDataFieldApp!)
                connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
            }
        }
    }

    private var lifetime = Lifetime()
    private var selectPromise: Future<[IQDevice], Never>.Promise?

    init(resolver: Resolver) {
        super.init()
        connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)
        injectServices(resolver)
        restoreDevices()
        subscribeToOpenFromGarminConnect()
        setupApplications()
        subscribeState()
    }

    private func subscribeToOpenFromGarminConnect() {
        notificationCenter
            .publisher(for: .openFromGarminConnect)
            .sink { notification in
                guard let url = notification.object as? URL else { return }
                self.parseDevicesFor(url: url)
            }
            .store(in: &lifetime)
    }

    private func subscribeState() {
        func sendToWatchface(state: NSDictionary) {
            watchfaces.forEach { app in
                connectIQ?.getAppStatus(app) { status in
                    guard status?.isInstalled ?? false else {
                        debug(.service, "Garmin: watchface app not installed")
                        return
                    }
                    debug(.service, "Garmin: sending message to watchface")
                    self.sendMessage(state, to: app)
                }
            }
        }

        stateSubject
            .throttle(for: .seconds(10), scheduler: DispatchQueue.main, latest: true)
            .sink { state in
                sendToWatchface(state: state)
            }
            .store(in: &lifetime)
    }

    private func restoreDevices() {
        devices = persistedDevices.map(\.iqDevice)
    }

    private func parseDevicesFor(url: URL) {
        devices = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice] ?? []
        selectPromise?(.success(devices))
        selectPromise = nil
    }

    private func setupApplications() {
        devices.forEach { _ in
        }
    }

    func selectDevices() -> AnyPublisher<[IQDevice], Never> {
        Future { promise in
            self.selectPromise = promise
            self.connectIQ?.showDeviceSelection()
        }
        .timeout(120, scheduler: DispatchQueue.main)
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func updateListDevices(devices: [IQDevice]) {
        self.devices = devices
    }

    func sendState(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary else {
            return
        }
        stateSubject.send(object)
    }

    private func sendMessage(_ msg: NSDictionary, to app: IQApp) {
        connectIQ?.sendMessage(msg, to: app, progress: { _, _ in
            // debug(.service, "Garmin: sending progress: \(Int(Double(sent) / Double(all) * 100)) %")
        }, completion: { result in
            if result == .success {
                debug(.service, "Garmin: message sent")
            } else {
                debug(.service, "Garmin: message failed")
            }
        })
    }
}

extension BaseGarminManager: IQUIOverrideDelegate {
    func needsToInstallConnectMobile() {
        debug(.apsManager, NSLocalizedString("Garmin is not available", comment: ""))
        let messageCont = MessageContent(
            content: NSLocalizedString(
                "The app Garmin Connect must be installed to use for Trio.\n Go to App Store to download it",
                comment: ""
            ),
            type: .warning
        )
        router.alertMessage.send(messageCont)
    }
}

extension BaseGarminManager: IQDeviceEventDelegate {
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        switch status {
        case .invalidDevice:
            debug(.service, "Garmin: invalidDevice, Device: \(device.uuid!)")
        case .bluetoothNotReady:
            debug(.service, "Garmin: bluetoothNotReady, Device: \(device.uuid!)")
        case .notFound:
            debug(.service, "Garmin: notFound, Device: \(device.uuid!)")
        case .notConnected:
            debug(.service, "Garmin: notConnected, Device: \(device.uuid!)")
        case .connected:
            debug(.service, "Garmin: connected, Device: \(device.uuid!)")
        @unknown default:
            debug(.service, "Garmin: unknown state, Device: \(device.uuid!)")
        }
    }
}

extension BaseGarminManager: IQAppMessageDelegate {
    func receivedMessage(_ message: Any, from app: IQApp) {
        print("ASDF: got message: \(message) from app: \(app.uuid!)")
        if let status = message as? String, status == "status", let watchState = stateRequet?() {
            sendState(watchState)
        }
    }
}

struct CodableDevice: Codable, Equatable {
    let id: UUID
    let modelName: String
    let friendlyName: String

    init(iqDevice: IQDevice) {
        id = iqDevice.uuid
        modelName = iqDevice.modelName
        friendlyName = iqDevice.modelName
    }

    var iqDevice: IQDevice {
        IQDevice(id: id, modelName: modelName, friendlyName: friendlyName)
    }
}
