import Foundation
@testable import Trio

/// Parks async calls until the test opens it, and lets the test wait until calls have arrived,
/// so suspended-operation tests do not depend on scheduling luck.
final class TestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen: Bool
    private var arrivals = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }

    var arrivalCount: Int { lock.withLock { arrivals } }

    func pass() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            arrivals += 1
            let reached = arrivalWaiters.filter { $0.count <= arrivals }
            arrivalWaiters.removeAll { $0.count <= arrivals }
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                parked.append(continuation)
                lock.unlock()
            }
            reached.forEach { $0.continuation.resume() }
        }
    }

    /// Counts an arrival from synchronous code without parking it.
    func arrive() {
        lock.lock()
        arrivals += 1
        let reached = arrivalWaiters.filter { $0.count <= arrivals }
        arrivalWaiters.removeAll { $0.count <= arrivals }
        lock.unlock()
        reached.forEach { $0.continuation.resume() }
    }

    func waitForArrivals(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if arrivals >= count {
                lock.unlock()
                continuation.resume()
            } else {
                arrivalWaiters.append((count, continuation))
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let waiting = parked
        parked = []
        lock.unlock()
        waiting.forEach { $0.resume() }
    }
}

/// A clock the test moves forward by hand, so expiry during a wait needs no real sleep.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date { lock.withLock { date } }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

/// Polls `condition` for up to two seconds; for state that has no callback to await.
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0 ..< 400 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}

/// Error whose every description carries a marker that must never reach a log or an ack.
struct SensitiveTestError: LocalizedError, CustomStringConvertible {
    static let marker = "SENSITIVE-7f3a"

    var description: String { "carbs=42g bolus=3.5U \(Self.marker)" }
    var errorDescription: String? { description }
}

/// Collects log lines from the injectable log sinks.
final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(level: WatchCommandLogger.Level, line: String)] = []

    var lines: [String] { lock.withLock { storage.map(\.line) } }
    var entries: [(level: WatchCommandLogger.Level, line: String)] { lock.withLock { storage } }

    var logger: WatchCommandLogger {
        WatchCommandLogger { [self] level, line, _, _, _ in record(line, level: level) }
    }

    func record(_ line: String, level: WatchCommandLogger.Level = .debug) {
        lock.withLock { storage.append((level, line)) }
    }
}
