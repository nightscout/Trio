import Foundation
import os

final class InMemoryLogSink: LogSink {
    private struct Ring: Sendable {
        var buffer: [LogRecord] = []
        var next = 0
    }

    let capacity: Int
    private let ring = OSAllocatedUnfairLock(initialState: Ring())

    init(capacity: Int = 5000) {
        self.capacity = max(1, capacity)
    }

    func accept(_ record: LogRecord) {
        ring.withLock { ring in
            if ring.buffer.count < capacity {
                ring.buffer.append(record)
            } else {
                ring.buffer[ring.next] = record
                ring.next = (ring.next + 1) % capacity
            }
        }
    }

    func flush() async {}

    func records(in window: DateInterval, minimumLevel: LogLevel) async -> [LogRecord] {
        snapshot().filter { window.contains($0.timestamp) && $0.level >= minimumLevel }
    }

    func snapshot() -> [LogRecord] {
        ring.withLock { ring in
            Array(ring.buffer[ring.next...] + ring.buffer[..<ring.next])
        }
    }
}
