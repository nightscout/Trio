import CoreBluetooth
import LoopKit
import LoopKitUI
import Swinject

protocol BluetoothStateManager: BluetoothProvider {}

public class BaseBluetoothStateManager: NSObject, BluetoothStateManager, Injectable {
    private var completion: ((BluetoothAuthorization) -> Void)?
    private var centralManager: CBCentralManager?
    private var bluetoothObservers = WeakSynchronizedSet<BluetoothObserver>()

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)
        if bluetoothAuthorization != .notDetermined {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    public var bluetoothAuthorization: BluetoothAuthorization {
        BluetoothAuthorization(CBCentralManager.authorization)
    }

    public var bluetoothState: BluetoothState {
        guard let centralManager = centralManager else {
            return .unknown
        }
        return BluetoothState(centralManager.state)
    }

    public func authorizeBluetooth(_ completion: @escaping (BluetoothAuthorization) -> Void) {
        guard centralManager == nil else {
            completion(bluetoothAuthorization)
            return
        }
        self.completion = completion
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func addBluetoothObserver(_ observer: BluetoothObserver, queue: DispatchQueue = .main) {
        bluetoothObservers.insert(observer, queue: queue)
    }

    public func removeBluetoothObserver(_ observer: BluetoothObserver) {
        bluetoothObservers.removeElement(observer)
    }
}

// MARK: - CBCentralManagerDelegate

extension BaseBluetoothStateManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if let completion = completion {
            completion(bluetoothAuthorization)
            self.completion = nil
        }
        bluetoothObservers.forEach { $0.bluetoothDidUpdateState(BluetoothState(central.state)) }
    }
}

// MARK: - BluetoothAuthorization

private extension BluetoothAuthorization {
    init(_ authorization: CBManagerAuthorization) {
        switch authorization {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .allowedAlways:
            self = .authorized
        @unknown default:
            self = .notDetermined
        }
    }
}

// MARK: - BluetoothState

private extension BluetoothState {
    init(_ state: CBManagerState) {
        switch state {
        case .unknown:
            self = .unknown
        case .resetting:
            self = .resetting
        case .unsupported:
            #if IOS_SIMULATOR
                self = .poweredOn // Simulator reports unsupported, but pretend it is powered on
            #else
                self = .unsupported
            #endif
        case .unauthorized:
            self = .unauthorized
        case .poweredOff:
            self = .poweredOff
        case .poweredOn:
            self = .poweredOn
        @unknown default:
            self = .unknown
        }
    }
}
