import Foundation

protocol Broadcaster {
    func register<T>(_ protocolType: T.Type, observer: T)
    func unregister<T>(_ protocolType: T.Type, observer: T)
    func unregister<T>(_ protocolType: T.Type)
    func notify<T>(_ protocolType: T.Type, on queue: DispatchQueue, block: @escaping (T) -> Void)
}

final class BaseBroadcaster: Broadcaster {
    func register<T>(_ protocolType: T.Type, observer: T) {
        SwiftNotificationCenter.register(protocolType, observer: observer)
    }

    func unregister<T>(_ protocolType: T.Type, observer: T) {
        SwiftNotificationCenter.unregister(protocolType, observer: observer)
    }

    func unregister<T>(_ protocolType: T.Type) {
        SwiftNotificationCenter.unregister(protocolType)
    }

    func notify<T>(_ protocolType: T.Type, on queue: DispatchQueue, block: @escaping (T) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        SwiftNotificationCenter.notify(protocolType, block: block)
    }
}
