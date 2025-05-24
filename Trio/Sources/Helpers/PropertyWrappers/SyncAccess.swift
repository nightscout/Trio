//
// Trio
// SyncAccess.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

@propertyWrapper class SyncAccess<T> {
    var wrappedValue: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    var projectedValue: SyncAccess<T> { self }

    private var value: T
    private let lock: NSRecursiveLock

    init(wrappedValue: T) {
        value = wrappedValue
        lock = NSRecursiveLock()
        lock.name = "SyncAccess::\(Unmanaged.passUnretained(self).toOpaque())"
    }

    init(wrappedValue: T, lock: NSRecursiveLock) {
        value = wrappedValue
        self.lock = lock
    }
}
