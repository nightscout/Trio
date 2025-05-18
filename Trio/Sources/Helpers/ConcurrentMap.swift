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
