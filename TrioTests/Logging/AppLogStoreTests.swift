import CoreData
import Foundation
import Testing
import UIKit

@testable import Trio

@Suite("App Log Store Tests", .serialized) struct AppLogStoreTests {
    private final class Loader: @unchecked Sendable {
        private let lock = NSLock()
        private var succeeds: Bool
        private var loaded = false

        init(succeeds: Bool) { self.succeeds = succeeds }

        var didLoad: Bool { lock.withLock { loaded } }
        func setSucceeds(_ value: Bool) { lock.withLock { succeeds = value } }

        func run(_ url: URL) -> NSPersistentContainer? {
            guard lock.withLock({ succeeds }), let container = AppLogStore.loadContainer(url) else { return nil }
            lock.withLock { loaded = true }
            return container
        }
    }

    private static func makeStore(
        policy: LogRetentionPolicy = .default,
        loader: Loader = Loader(succeeds: true),
        center: Foundation.NotificationCenter = Foundation.NotificationCenter(),
        isProtectedDataAvailable: @escaping @MainActor() -> Bool = { true }
    ) throws -> (store: AppLogStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppLogStore(
            storageURL: directory.appendingPathComponent("logs/AppLog.sqlite"),
            policy: policy,
            notificationCenter: center,
            loadContainer: loader.run,
            isProtectedDataAvailable: isProtectedDataAvailable
        )
        return (store, directory)
    }

    private static func record(_ index: Int, at date: Date, level: LogLevel = .info) -> LogRecord {
        LogRecord(
            timestamp: date,
            level: level,
            category: "Service",
            message: "message \(index)",
            file: "File.swift",
            function: "run()",
            line: UInt(index),
            launchID: LaunchID.current
        )
    }

    // Generous: the main actor is busy when the whole suite runs
    private static func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0 ..< 400 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static let everything = DateInterval(start: .distantPast, end: .distantFuture)

    @Test("Records round-trip in order") func roundTrip() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date().addingTimeInterval(-60)
        let records = (0 ..< 1000).map { Self.record($0, at: start.addingTimeInterval(Double($0) / 1000)) }

        records.forEach(store.accept)
        await store.flush()

        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(stored == records)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("logs/AppLog.sqlite").path))
    }

    @Test("Flush throughput") func throughput() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.flush()
        let now = Date()
        let records = (0 ..< 4000).map { Self.record($0, at: now) }

        let clock = ContinuousClock()
        let acceptDuration = clock.measure { records.forEach(store.accept) }
        let flushDuration = await clock.measure { await store.flush() }
        print("AppLogStore: accepted 4000 in \(acceptDuration), flushed in \(flushDuration)")
        #expect(await store.records(in: Self.everything, minimumLevel: .debug).count == 4000)
    }

    @Test("Purges records older than the maximum age") func agePurge() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        store.accept(Self.record(0, at: now.addingTimeInterval(-2 * 60 * 60)))
        store.accept(Self.record(1, at: now.addingTimeInterval(-10)))
        await store.flush()

        var policy = LogRetentionPolicy.default
        policy.maxAge = 60 * 60
        store.apply(policy)

        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(stored.map(\.message) == ["message 1"])
    }

    @Test("Purges several days of old records a day at a time while logging continues") func purgesByDay() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        var policy = LogRetentionPolicy.default
        policy.maxAge = 2 * 24 * 60 * 60
        let cutoff = now.addingTimeInterval(-policy.maxAge)
        let dates = stride(from: 10 * 24.0, to: 0, by: -1).map { now.addingTimeInterval(-$0 * 60 * 60 - 120) }
            + [cutoff.addingTimeInterval(-300), cutoff.addingTimeInterval(300)]
        let seeded = dates.sorted().enumerated().map { Self.record($0.offset, at: $0.element) }
        seeded.forEach(store.accept)
        await store.flush()

        store.apply(policy)
        let during = (0 ..< 50).map { Self.record(1000 + $0, at: Date()) }
        during.forEach(store.accept)
        let early = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(early.contains { $0.timestamp < cutoff })

        #expect(await Self.waitUntil {
            await store.records(in: Self.everything, minimumLevel: .debug).allSatisfy { $0.timestamp >= cutoff }
        })
        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(stored == seeded.filter { $0.timestamp >= cutoff } + during)
    }

    @Test("Keeps only the newest rows over the cap") func rowCapPurge() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date().addingTimeInterval(-60)
        (0 ..< 50).forEach { store.accept(Self.record($0, at: start.addingTimeInterval(Double($0)))) }
        await store.flush()

        var policy = LogRetentionPolicy.default
        policy.maxRows = 10
        store.apply(policy)

        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(stored.map(\.message) == (40 ..< 50).map { "message \($0)" })
    }

    @Test("Drops debug records when verbose logging is off") func dropsDebug() async throws {
        var policy = LogRetentionPolicy.default
        policy.persistsDebug = false
        let (store, directory) = try Self.makeStore(policy: policy)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        store.accept(Self.record(0, at: now, level: .debug))
        store.accept(Self.record(1, at: now, level: .info))
        await store.flush()

        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(stored.map(\.message) == ["message 1"])
    }

    @Test("Lone surrogates and NUL bytes are stored without losing the batch") func sanitizesStrings() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let surrogate = LogRecord(
            timestamp: now,
            level: .info,
            category: "Service",
            message: String(utf16CodeUnits: [0x61, 0xD800, 0x62], count: 3),
            file: "File.swift",
            function: "run()",
            line: 1,
            launchID: LaunchID.current
        )
        let nul = LogRecord(
            timestamp: now.addingTimeInterval(1),
            level: .info,
            category: "Service",
            message: "a\u{0}b",
            file: "File.swift",
            function: "run()",
            line: 2,
            launchID: LaunchID.current
        )
        let records = [
            Self.record(0, at: now.addingTimeInterval(-1)),
            surrogate,
            nul,
            Self.record(3, at: now.addingTimeInterval(2))
        ]
        records.forEach(store.accept)
        await store.flush()

        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(stored.map(\.message) == ["message 0", "a\u{FFFD}b", "a\u{FFFD}b", "message 3"])
    }

    @Test("Buffered records drain in order once the store opens") func drainsBuffer() async throws {
        let loader = Loader(succeeds: false)
        let center = Foundation.NotificationCenter()
        let (store, directory) = try Self.makeStore(loader: loader, center: center, isProtectedDataAvailable: { false })
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date().addingTimeInterval(-60)
        let records = (0 ..< 300).map { Self.record($0, at: start.addingTimeInterval(Double($0))) }

        records.forEach(store.accept)
        await store.flush()
        #expect(!loader.didLoad)
        #expect(await store.records(in: Self.everything, minimumLevel: .debug) == records)

        loader.setSucceeds(true)
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        #expect(await Self.waitUntil { loader.didLoad })
        #expect(await store.records(in: Self.everything, minimumLevel: .debug) == records)
    }

    @Test("An unlock during the protected-data check still opens the store") func unlockDuringCheck() async throws {
        let loader = Loader(succeeds: false)
        let center = Foundation.NotificationCenter()
        let (store, directory) = try Self.makeStore(loader: loader, center: center, isProtectedDataAvailable: {
            Thread.sleep(forTimeInterval: 0.3)
            return false
        })
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = store

        try await Task.sleep(nanoseconds: 100_000_000)
        loader.setSucceeds(true)
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        #expect(await Self.waitUntil { loader.didLoad })
    }

    @Test("Equal timestamps come back in the order they were stored") func equalTimestampsKeepOrder() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date()
        for batch in 0 ..< 5 {
            (batch * 100 ..< batch * 100 + 100).forEach { store.accept(Self.record($0, at: date)) }
            await store.flush()
        }
        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        #expect(stored.map(\.line) == Array(0 ..< 500).map(UInt.init))
    }

    @Test("Moved-aside stores older than 7 days are deleted on open") func removesOldUnreadableStores() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logs = directory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let now = Int(Date().timeIntervalSince1970)
        let old = now - 8 * 24 * 60 * 60
        let expired = ["AppLog.sqlite.unreadable-\(old)", "AppLog.sqlite-wal.unreadable-\(old)"]
        let kept = [
            "AppLog.sqlite.unreadable-\(now - 24 * 60 * 60)",
            "AppLog.sqlite.unreadable-unknown",
            "DeviceLog.sqlite.unreadable-\(old)"
        ]
        for name in expired + kept {
            FileManager.default.createFile(atPath: logs.appendingPathComponent(name).path, contents: Data([1]))
        }
        let store = AppLogStore(
            storageURL: logs.appendingPathComponent("AppLog.sqlite"),
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        await store.flush()
        let remaining = try FileManager.default.contentsOfDirectory(atPath: logs.path).filter { $0.contains(".unreadable-") }
        #expect(Set(remaining) == Set(kept))
    }
}
