//
// Trio
// ConcurrentMap.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

extension Collection where Index == Int {
    func concurrentMap<T>(_ transform: (Element) -> T) -> [T] {
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: count * MemoryLayout<T>.stride,
            alignment: MemoryLayout<T>.alignment
        ).bindMemory(to: T.self, capacity: count)

        DispatchQueue.concurrentPerform(iterations: count) { index in
            let element = self[index]
            let transformedElement = transform(element)
            buffer[index] = transformedElement
        }

        return [T](UnsafeBufferPointer(start: buffer, count: count))
    }
}
