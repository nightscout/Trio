// Trio
// NSLocking+Extensions.swift
// Created by Ivan Valkou on 2021-03-07.

import Foundation

extension NSLocking {
    func perform<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}

extension NSRecursiveLock {
    convenience init(label: String) {
        self.init()
        name = label
    }
}

extension NSLock {
    convenience init(label: String) {
        self.init()
        name = label
    }
}
