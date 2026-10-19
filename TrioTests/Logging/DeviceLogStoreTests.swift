import Foundation
import LoopKit
import Testing
import UIKit

@testable import Trio

@Suite("Device Log Store Tests", .serialized) struct DeviceLogStoreTests {
    private final class Preflight: @unchecked Sendable {
        private let lock = NSLock()
        private var succeeds: Bool
        private var calls = 0

        init(succeeds: Bool) { self.succeeds = succeeds }

        var callCount: Int { lock.withLock { calls } }
        func setSucceeds(_ value: Bool) { lock.withLock { succeeds = value } }

        func run(_ url: URL) -> Bool {
            let shouldSucceed = lock.withLock {
                calls += 1
                return succeeds
            }
            return shouldSucceed && DeviceLogStore.preflight(url)
        }
    }

    private static func makeStorageURL() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("Logs/DeviceLog.sqlite"))
    }

    private static var window: DateInterval {
        DateInterval(start: Date().addingTimeInterval(-60), end: Date().addingTimeInterval(60))
    }

    private static func log(_ store: DeviceLogStore, manager: String, message: String) async -> Error? {
        await withCheckedContinuation { continuation in
            store.log(managerIdentifier: manager, deviceIdentifier: "device-1", type: .send, message: message) {
                continuation.resume(returning: $0)
            }
        }
    }

    // Generous: the main actor is busy when the whole suite runs
    private static func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0 ..< 400 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    @Test("Entries are filtered by manager and ordered by time") func filtersAndOrders() async throws {
        let (directory, file) = try Self.makeStorageURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceLogStore(storageURL: file, isProtectedDataAvailable: { true })

        #expect(await Self.log(store, manager: "com.example.pump", message: "first") == nil)
        #expect(await Self.log(store, manager: "com.example.cgm", message: "second") == nil)
        #expect(await Self.log(store, manager: "com.example.pump", message: "third") == nil)

        let all = await store.entries(in: Self.window)
        #expect(all.map(\.message) == ["first", "second", "third"])

        let pump = await store.entries(in: Self.window, managerIdentifier: "com.example.pump")
        #expect(pump.map(\.message) == ["first", "third"])
        #expect(pump.allSatisfy { $0.deviceIdentifier == "device-1" && $0.type == .send })

        let cgm = await store.entries(in: Self.window, managerIdentifier: "com.example.cgm")
        #expect(cgm.map(\.message) == ["second"])
    }

    @Test("Buffered entries drain once the store opens") func drainsBuffer() async throws {
        let (directory, file) = try Self.makeStorageURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preflight = Preflight(succeeds: false)
        let center = Foundation.NotificationCenter()
        let store = DeviceLogStore(
            storageURL: file,
            notificationCenter: center,
            preflight: preflight.run,
            isProtectedDataAvailable: { true }
        )

        #expect(await Self.waitUntil { preflight.callCount == 3 })
        #expect(await Self.log(store, manager: "com.example.pump", message: "buffered-1") == nil)
        #expect(await Self.log(store, manager: "com.example.cgm", message: "buffered-2") == nil)
        #expect(await store.entries(in: Self.window).map(\.message) == ["buffered-1", "buffered-2"])
        #expect(await store.entries(in: Self.window, managerIdentifier: "com.example.cgm").map(\.message) == ["buffered-2"])

        preflight.setSucceeds(true)
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        #expect(await Self.waitUntil {
            await store.entries(in: Self.window).filter { $0.message.hasPrefix("[queued ") }.count == 2
        })
        let entries = await store.entries(in: Self.window)
        #expect(entries.count == 2)
        let pattern = try NSRegularExpression(pattern: #"^\[queued \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\] buffered-(\d)$"#)
        let suffixes = entries.compactMap { entry -> String? in
            let range = NSRange(entry.message.startIndex..., in: entry.message)
            guard let match = pattern.firstMatch(in: entry.message, range: range),
                  let suffix = Range(match.range(at: 1), in: entry.message)
            else { return nil }
            return String(entry.message[suffix])
        }
        #expect(suffixes == ["1", "2"])
    }

    @Test("Store is left in place while protected data is unavailable") func keepsStoreWhileLocked() async throws {
        let (directory, file) = try Self.makeStorageURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: file)
        let preflight = Preflight(succeeds: false)
        let store = DeviceLogStore(
            storageURL: file,
            notificationCenter: Foundation.NotificationCenter(),
            preflight: preflight.run,
            isProtectedDataAvailable: { false }
        )

        #expect(await Self.log(store, manager: "com.example.pump", message: "locked") == nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(preflight.callCount == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Moved-aside stores older than 7 days are deleted on open") func removesOldUnreadableStores() async throws {
        let (directory, file) = try Self.makeStorageURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logs = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let now = Int(Date().timeIntervalSince1970)
        let old = now - 8 * 24 * 60 * 60
        let expired = ["DeviceLog.sqlite.unreadable-\(old)", "DeviceLog.sqlite-shm.unreadable-\(old)"]
        let kept = ["DeviceLog.sqlite.unreadable-\(now - 60)", "AppLog.sqlite.unreadable-\(old)"]
        for name in expired + kept {
            FileManager.default.createFile(atPath: logs.appendingPathComponent(name).path, contents: Data([1]))
        }
        let store = DeviceLogStore(
            storageURL: file,
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        _ = await store.entries(in: Self.window)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: logs.path).filter { $0.contains(".unreadable-") }
        #expect(Set(remaining) == Set(kept))
    }
}
