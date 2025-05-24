//
// Trio
// Broadcaster.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

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
