//
// Trio
// NSLocking+Extensions.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

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
