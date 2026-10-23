import CoreData
import CryptoKit
import Foundation
import LoopKit
import Testing
import UIKit

@testable import Trio

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1E18
    }
}

@Suite(
    "Logging Robustness Stress Tests",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["TRIO_STRESS"] == "1")
) struct LoggingRobustnessStressTests {
    enum Corruption: String, CaseIterable, Sendable {
        case garbage
        case truncated
        case truncatedHeader
        case directory
        case readOnlyFile
        case readOnlyDirectory
    }

    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) { self.value = value }

        func get() -> Value { lock.withLock { value } }
        func set(_ newValue: Value) { lock.withLock { value = newValue } }
        @discardableResult func update<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
    }

    private final class Loader: @unchecked Sendable {
        let calls = Box(0)
        let successes = Box(0)
        private let fails: (Int) -> Bool

        init(fails: @escaping (Int) -> Bool = { _ in false }) { self.fails = fails }

        func run(_ url: URL) -> NSPersistentContainer? {
            let index = calls.update { count -> Int in
                count += 1
                return count - 1
            }
            guard !fails(index), let container = AppLogStore.loadContainer(url) else { return nil }
            successes.update { $0 += 1 }
            return container
        }
    }

    private final class Preflight: @unchecked Sendable {
        let calls = Box(0)
        let successes = Box(0)
        private let fails: (Int) -> Bool

        init(fails: @escaping (Int) -> Bool = { _ in false }) { self.fails = fails }

        func run(_ url: URL) -> Bool {
            let index = calls.update { count -> Int in
                count += 1
                return count - 1
            }
            guard !fails(index), DeviceLogStore.preflight(url) else { return false }
            successes.update { $0 += 1 }
            return true
        }
    }

    private class StubManager: DeviceManager {
        class var pluginIdentifier: String { "com.example.pump" }
        var localizedTitle: String { "Example Pump" }
        var debugDescription: String { "## StubManager\nserial: SYN-DEV-0042" }
        var rawState: RawStateValue { [:] }
        var isOnboarded: Bool { true }

        init() {}
        required init?(rawState _: RawStateValue) {}

        func acknowledgeAlert(alertIdentifier _: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
            completion(nil)
        }

        func getSoundBaseURL() -> URL? { nil }
        func getSounds() -> [Alert.Sound] { [] }
        func initializationComplete(for _: [Pluggable]) {}
    }

    private final class StubCGMManager: StubManager {
        override class var pluginIdentifier: String { "com.example.cgm" }
        override var localizedTitle: String { "Example CGM" }
    }

    private static let everything = DateInterval(start: .distantPast, end: .distantFuture)
    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 24 * 60 * 60

    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func record(_ message: String, at date: Date, level: LogLevel = .info) -> LogRecord {
        LogRecord(
            timestamp: date,
            level: level,
            category: "Stress",
            message: message,
            file: "Stress.swift",
            function: "run()",
            line: 1,
            launchID: LaunchID.current
        )
    }

    private static func waitUntil(attempts: Int = 600, _ condition: () async -> Bool) async -> Bool {
        for _ in 0 ..< attempts {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    @discardableResult private static func logDevice(
        _ store: DeviceLogStore,
        _ message: String,
        manager: String = "com.example.pump",
        device: String? = "SYN-DEV-0001"
    ) async -> Error? {
        await withCheckedContinuation { continuation in
            store.log(managerIdentifier: manager, deviceIdentifier: device, type: .send, message: message) {
                continuation.resume(returning: $0)
            }
        }
    }

    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    private static func percentile(_ sorted: [UInt64], _ fraction: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }

    private static func movedAside(_ url: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        return names.filter { $0.hasPrefix(url.lastPathComponent + ".unreadable-") }
    }

    private static func populateStore(
        at url: URL,
        model name: String,
        bundle: Bundle,
        entity: String,
        count: Int,
        row: @escaping (Int) -> [String: Any]
    ) throws {
        guard let modelURL = bundle.url(forResource: name, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL)
        else { throw CocoaError(.fileReadNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: url,
            options: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]]
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        var index = 0
        let request = NSBatchInsertRequest(entityName: entity, dictionaryHandler: { dictionary in
            guard index < count else { return true }
            dictionary.addEntries(from: row(index))
            index += 1
            return false
        })
        try context.performAndWait { _ = try context.execute(request) }
        try coordinator.remove(store)
    }

    private static func populateAppLog(at url: URL, count: Int, start: Date, step: TimeInterval = 1) throws {
        try populateStore(at: url, model: "AppLog", bundle: .main, entity: "AppLogEntry", count: count) { index in
            [
                "timestamp": start.addingTimeInterval(Double(index) * step),
                "level": LogLevel.info.rawValue,
                "category": "Stress",
                "message": "seed \(index)",
                "file": "Stress.swift",
                "function": "run()",
                "line": Int32(1),
                "launchID": UUID()
            ]
        }
    }

    private static func populateDeviceLog(at url: URL, count: Int, start: Date) throws {
        try populateStore(
            at: url,
            model: "DeviceLog",
            bundle: Bundle(for: PersistentDeviceLog.self),
            entity: "Entry",
            count: count
        ) { index in
            [
                "timestamp": start.addingTimeInterval(Double(index)),
                "managerIdentifier": "com.example.pump",
                "deviceIdentifier": "SYN-DEV-0001",
                "type": DeviceLogEntryType.send.rawValue,
                "message": "seed \(index)",
                "modificationCounter": Int64(index + 1)
            ]
        }
    }

    private static func corrupt(_ url: URL, _ corruption: Corruption, populate: (URL) throws -> Void) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch corruption {
        case .garbage:
            try Data((0 ..< 65536).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: url)
        case .truncated,
             .truncatedHeader:
            try populate(url)
            let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: corruption == .truncated ? size / 2 : 50)
            try handle.close()
        case .directory:
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("not a store".utf8).write(to: url.appendingPathComponent("inside.txt"))
        case .readOnlyFile:
            try populate(url)
            try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        case .readOnlyDirectory:
            try populate(url)
            try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.deletingLastPathComponent().path)
        }
    }

    private static func restorePermissions(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    private static func export(
        _ kind: LogExport.Kind,
        appLog: any LogSink,
        deviceLogStore: DeviceLogStore
    ) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = LogExport(appLog: appLog, deviceLogStore: deviceLogStore, pump: nil, cgm: nil)
        let url = try await export.writeLog(kind, days: 1, into: directory)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func write(
        _ lines: [LogLine],
        window: DateInterval,
        header: String = "Header",
        redactor: Redactor = Redactor(exactValues: [])
    ) async throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try await LogFileWriter.write(header: header, window: window, to: url, redactor: redactor) { _ in lines }
        return try Data(contentsOf: url)
    }

    private static func body(_ text: String) -> String {
        guard let range = text.range(of: "\n== Log ==\n") else { return "" }
        return String(text[range.upperBound...])
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: Concurrency

    @Test("64 producers log through the free functions while flush, read and purge run") func concurrentProducers() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var basePolicy = LogRetentionPolicy.default
        basePolicy.maxRows = 5_000_000
        let store = AppLogStore(
            storageURL: directory.appendingPathComponent("logs/AppLog.sqlite"),
            policy: basePolicy,
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        await store.flush()
        let previous = TrioLogger.sink
        TrioLogger.install(store)
        defer { TrioLogger.install(previous) }

        let token = "stress-\(UUID().uuidString.prefix(8))"
        let producers = 64
        let perProducer = 20000
        let followUp = 50
        let start = Date()
        let running = Box(true)
        let chaos = Task { () -> (Int, Duration) in
            var rounds = 0
            var slowest = Duration.zero
            var policy = basePolicy
            let clock = ContinuousClock()
            while running.get() {
                let round = await clock.measure {
                    await store.flush()
                    _ = await store.records(
                        in: DateInterval(start: Date().addingTimeInterval(-1), end: Date()),
                        minimumLevel: .warning
                    )
                }
                slowest = max(slowest, round)
                policy.maxAge = policy.maxAge == basePolicy.maxAge ? 6 * Self.day : basePolicy.maxAge
                store.apply(policy)
                rounds += 1
            }
            return (rounds, slowest)
        }

        let footprintBefore = Self.footprint()
        let clock = ContinuousClock()
        var latencies: [UInt64] = []
        let elapsed = await clock.measure {
            latencies = await withTaskGroup(of: [UInt64].self) { group in
                for producer in 0 ..< producers {
                    group.addTask {
                        var samples: [UInt64] = []
                        samples.reserveCapacity(perProducer)
                        for index in 0 ..< perProducer {
                            let begin = DispatchTime.now().uptimeNanoseconds
                            info(.loop, "\(token) \(producer) \(index)")
                            samples.append(DispatchTime.now().uptimeNanoseconds - begin)
                        }
                        return samples
                    }
                }
                return await group.reduce(into: []) { $0 += $1 }
            }
        }
        let footprintPeak = Self.footprint()
        running.set(false)
        let (rounds, slowestRound) = await chaos.value

        // Below the buffer cap nothing may be dropped, however flushes interleave
        await withTaskGroup(of: Void.self) { group in
            for producer in 0 ..< producers {
                group.addTask {
                    for index in perProducer ..< perProducer + followUp {
                        info(.loop, "\(token) \(producer) \(index)")
                    }
                }
            }
        }
        await store.flush()

        // Same load without os_log isolates the sink's share of caller latency
        var quiet = await withTaskGroup(of: [UInt64].self) { group in
            for _ in 0 ..< producers {
                group.addTask {
                    (0 ..< 5000).map { index -> UInt64 in
                        let begin = DispatchTime.now().uptimeNanoseconds
                        debug(.loop, "quiet \(index)", printToConsole: false)
                        return DispatchTime.now().uptimeNanoseconds - begin
                    }
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
        quiet.sort()
        print(
            "STRESS: sink-only caller p50 \(Self.percentile(quiet, 0.5)) ns " +
                "p99 \(Self.percentile(quiet, 0.99)) ns max \(quiet.last ?? 0) ns"
        )
        await store.flush()

        let stored = await store.records(in: DateInterval(start: start, end: Date().addingTimeInterval(1)), minimumLevel: .debug)
            .filter { $0.message.hasPrefix(token + " ") }
        var seen = Set<Int>()
        var lastIndex = [Int](repeating: -1, count: producers)
        var lastDate = [Date](repeating: .distantPast, count: producers)
        var duplicates = 0
        var outOfOrder = 0
        var followUpSeen = 0
        var inversions: [String] = []
        for record in stored {
            let parts = record.message.split(separator: " ")
            guard parts.count == 3, let producer = Int(parts[1]), let index = Int(parts[2]) else { continue }
            if !seen.insert(producer * (perProducer + followUp) + index).inserted { duplicates += 1 }
            if index <= lastIndex[producer] {
                outOfOrder += 1
                if inversions.count < 5 {
                    let gap = record.timestamp.timeIntervalSince(lastDate[producer])
                    inversions.append("p\(producer) \(lastIndex[producer])->\(index) gap \(gap)")
                }
            }
            lastIndex[producer] = index
            lastDate[producer] = record.timestamp
            if index >= perProducer { followUpSeen += 1 }
        }
        let burstStored = seen.count - followUpSeen
        let total = producers * perProducer
        latencies.sort()
        print(
            "STRESS: concurrency \(producers)x\(perProducer) in \(elapsed), \(Int(Double(total) / elapsed.seconds)) calls/s, " +
                "stored \(burstStored)/\(total) (dropped \(total - burstStored)), chaos rounds \(rounds) slowest \(slowestRound), " +
                "caller p50 \(Self.percentile(latencies, 0.5)) ns p99 \(Self.percentile(latencies, 0.99)) ns " +
                "p99.9 \(Self.percentile(latencies, 0.999)) ns max \(latencies.last ?? 0) ns, " +
                "footprint +\((footprintPeak - footprintBefore) / 1_048_576) MB"
        )
        print("STRESS: per-producer inversions \(outOfOrder) \(inversions)")
        #expect(duplicates == 0)
        #expect(outOfOrder == 0)
        #expect(followUpSeen == producers * followUp)
        #expect(burstStored > 0)
    }

    // MARK: Burst while unavailable

    @Test("50 000 records while the app log store is locked keep the newest, in order") func appLogBurstWhileLocked() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let locked = Box(true)
        let loader = Loader { _ in locked.get() }
        let center = Foundation.NotificationCenter()
        let store = AppLogStore(
            storageURL: directory.appendingPathComponent("logs/AppLog.sqlite"),
            notificationCenter: center,
            loadContainer: loader.run,
            isProtectedDataAvailable: { !locked.get() }
        )
        await store.flush()

        let count = 50000
        let start = Date().addingTimeInterval(-Self.hour)
        let padding = String(repeating: "x", count: 200)
        let records = (0 ..< count).map { Self.record("burst \($0) \(padding)", at: start.addingTimeInterval(Double($0) / 100)) }
        var expected = 0
        for _ in 0 ..< count {
            expected += 1
            if expected > AppLogStore.bufferLimit { expected = AppLogStore.bufferLimit - AppLogStore.bufferLimit / 10 }
        }

        let footprintBefore = Self.footprint()
        let clock = ContinuousClock()
        let acceptTime = clock.measure { records.forEach(store.accept) }
        let buffered = await store.records(in: Self.everything, minimumLevel: .debug)
        let footprintDelta = Self.footprint() - footprintBefore

        #expect(loader.successes.get() == 0)
        #expect(buffered.count == expected)
        #expect(buffered == Array(records.suffix(expected)))
        #expect(footprintDelta < 64 * 1_048_576)

        locked.set(false)
        let drainStart = clock.now
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        #expect(await Self.waitUntil { loader.successes.get() == 1 })
        let drained = await store.records(in: Self.everything, minimumLevel: .debug)
        let drainTime = clock.now - drainStart
        #expect(drained == Array(records.suffix(expected)))
        print(
            "STRESS: app log burst \(count) accepted in \(acceptTime), buffered \(buffered.count), " +
                "footprint +\(footprintDelta / 1024) KB, drained \(drained.count) in \(drainTime)"
        )
    }

    @Test("50 000 device entries while locked keep the newest 5 000 with their queued time") func deviceLogBurstWhileLocked() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let locked = Box(true)
        let preflight = Preflight { _ in locked.get() }
        let center = Foundation.NotificationCenter()
        let store = DeviceLogStore(
            storageURL: directory.appendingPathComponent("logs/DeviceLog.sqlite"),
            notificationCenter: center,
            preflight: preflight.run,
            isProtectedDataAvailable: { !locked.get() }
        )

        let count = 50000
        let before = Date()
        let footprintBefore = Self.footprint()
        let clock = ContinuousClock()
        let bufferTime = await clock.measure {
            for index in 0 ..< count - 1 {
                store.log(
                    managerIdentifier: "com.example.pump",
                    deviceIdentifier: "SYN-DEV-0001",
                    type: .send,
                    message: "burst \(index)"
                )
            }
            await Self.logDevice(store, "burst \(count - 1)")
        }
        let footprintDelta = Self.footprint() - footprintBefore
        let after = Date()
        #expect(preflight.successes.get() == 0)
        #expect(footprintDelta < 64 * 1_048_576)

        locked.set(false)
        let drainStart = clock.now
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        #expect(await Self.waitUntil(attempts: 2400) {
            await store.entries(in: Self.everything).count >= DeviceLogStore.bufferLimit
        })
        let drainTime = clock.now - drainStart
        let entries = await store.entries(in: Self.everything)

        let pattern = try NSRegularExpression(pattern: #"^\[queued ([^\]]+)\] burst (\d+)$"#)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var indexes: [Int] = []
        var queuedDates: [Date] = []
        for entry in entries {
            let range = NSRange(entry.message.startIndex..., in: entry.message)
            guard let match = pattern.firstMatch(in: entry.message, range: range),
                  let dateRange = Range(match.range(at: 1), in: entry.message),
                  let indexRange = Range(match.range(at: 2), in: entry.message),
                  let date = parser.date(from: String(entry.message[dateRange])),
                  let index = Int(entry.message[indexRange])
            else { continue }
            indexes.append(index)
            queuedDates.append(date)
        }
        #expect(entries.count == DeviceLogStore.bufferLimit)
        #expect(indexes == Array(count - DeviceLogStore.bufferLimit ..< count))
        #expect(zip(queuedDates, queuedDates.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(queuedDates.allSatisfy { $0 >= before.addingTimeInterval(-0.001) && $0 <= after.addingTimeInterval(0.001) })
        #expect(preflight.successes.get() == 1)
        print(
            "STRESS: device log burst \(count) buffered in \(bufferTime), footprint +\(footprintDelta / 1024) KB, " +
                "drained \(entries.count) in \(drainTime)"
        )
    }

    @Test("Device entries buffered while the store is unavailable reach the export") func bufferedDeviceEntriesExported() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceLogStore(
            storageURL: directory.appendingPathComponent("logs/DeviceLog.sqlite"),
            notificationCenter: Foundation.NotificationCenter(),
            preflight: { _ in false },
            isProtectedDataAvailable: { false }
        )
        for index in 0 ..< 20 {
            await Self.logDevice(store, "pending \(index)")
        }
        let entries = await store.entries(in: Self.everything)
        let text = try await Self.export(.all, appLog: InMemoryLogSink(), deviceLogStore: store)

        #expect(entries.count == 20)
        #expect(Self.occurrences(of: "[send] pending ", in: Self.body(text)) == 20)
    }

    // MARK: Corrupt stores

    @Test(
        "Corrupt app log store is moved aside once and logging continues",
        arguments: Corruption.allCases
    ) func corruptAppLogStore(_ corruption: Corruption) async throws {
        let directory = try Self.makeDirectory()
        let url = directory.appendingPathComponent("logs/AppLog.sqlite")
        defer {
            Self.restorePermissions(url)
            try? FileManager.default.removeItem(at: directory)
        }
        try Self
            .corrupt(url, corruption) {
                try Self.populateAppLog(at: $0, count: 5000, start: Date().addingTimeInterval(-Self.hour)) }
        let loader = Loader()
        let center = Foundation.NotificationCenter()
        let store = AppLogStore(
            storageURL: url,
            notificationCenter: center,
            loadContainer: loader.run,
            isProtectedDataAvailable: { true }
        )
        #expect(await Self.waitUntil { loader.successes.get() == 1 || loader.calls.get() >= 2 })

        let token = "corrupt-\(corruption.rawValue)"
        let start = Date().addingTimeInterval(-1)
        let records = (0 ..< 20).map { Self.record("\(token) \($0)", at: start.addingTimeInterval(Double($0) / 1000)) }
        records.forEach(store.accept)
        for _ in 0 ..< 5 {
            center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        }
        await store.flush()

        let stored = await store.records(in: Self.everything, minimumLevel: .debug).filter { $0.message.hasPrefix(token) }
        let deviceStore = DeviceLogStore(
            storageURL: directory.appendingPathComponent("device/DeviceLog.sqlite"),
            notificationCenter: center,
            isProtectedDataAvailable: { true }
        )
        let text = try await Self.export(.all, appLog: store, deviceLogStore: deviceStore)
        let exported = Self.occurrences(of: "[Stress] \(token) ", in: Self.body(text))
        Self.restorePermissions(url)
        let moved = Self.movedAside(url)
        print(
            "STRESS: corrupt app log \(corruption.rawValue): loads \(loader.calls.get()) ok \(loader.successes.get()), " +
                "moved aside \(moved.count), stored \(stored.count)/20, exported \(exported)"
        )

        #expect(moved.count <= 1)
        #expect(loader.successes.get() <= 1)
        switch corruption {
        case .directory,
             .garbage,
             .truncatedHeader:
            #expect(moved.count == 1)
            #expect(loader.successes.get() == 1)
        case .readOnlyDirectory:
            #expect(loader.successes.get() == 0)
        case .truncated:
            #expect(loader.successes.get() == 1)
        case .readOnlyFile:
            break
        }
        #expect(stored == records)
        #expect(exported == 20)
    }

    @Test("An app log store that rejects writes after opening keeps its records") func appLogStoreTurnsReadOnly() async throws {
        let directory = try Self.makeDirectory()
        let url = directory.appendingPathComponent("logs/AppLog.sqlite")
        defer {
            Self.restorePermissions(url)
            try? FileManager.default.removeItem(at: directory)
        }
        try Self.corrupt(url, .readOnlyFile) {
            try Self.populateAppLog(at: $0, count: 10, start: Date().addingTimeInterval(-Self.hour))
        }
        let calls = Box(0)
        let store = AppLogStore(
            storageURL: url,
            notificationCenter: Foundation.NotificationCenter(),
            loadContainer: { url in
                let call = calls.update { count -> Int in
                    count += 1
                    return count - 1
                }
                guard call == 0 else { return AppLogStore.loadContainer(url) }
                guard let modelURL = Bundle.main.url(forResource: "AppLog", withExtension: "momd"),
                      let model = NSManagedObjectModel(contentsOf: modelURL)
                else { return nil }
                let container = NSPersistentContainer(name: "AppLog", managedObjectModel: model)
                let description = NSPersistentStoreDescription(url: url)
                description.shouldAddStoreAsynchronously = false
                container.persistentStoreDescriptions = [description]
                container.loadPersistentStores { _, _ in }
                return container
            },
            isProtectedDataAvailable: { true }
        )
        await store.flush()

        let start = Date().addingTimeInterval(-1)
        let records = (0 ..< 20).map { Self.record("read-only \($0)", at: start.addingTimeInterval(Double($0) / 1000)) }
        records.forEach(store.accept)
        await store.flush()
        func readBack() async -> [LogRecord] {
            await store.records(in: Self.everything, minimumLevel: .debug).filter { $0.message.hasPrefix("read-only ") }
        }
        #expect(await Self.waitUntil { await readBack().count == records.count })
        let stored = await readBack()
        Self.restorePermissions(url)
        print(
            "STRESS: app log turned read-only: loads \(calls.get()), moved aside \(Self.movedAside(url).count), stored \(stored.count)"
        )
        #expect(stored == records)
        #expect(Self.movedAside(url).count == 1)
    }

    @Test(
        "Corrupt device log store never reaches PersistentDeviceLog's fatalError",
        arguments: Corruption.allCases
    ) func corruptDeviceLogStore(_ corruption: Corruption) async throws {
        let directory = try Self.makeDirectory()
        let url = directory.appendingPathComponent("logs/DeviceLog.sqlite")
        defer {
            Self.restorePermissions(url)
            try? FileManager.default.removeItem(at: directory)
        }
        try Self.corrupt(url, corruption) {
            try Self.populateDeviceLog(at: $0, count: 5000, start: Date().addingTimeInterval(-Self.hour))
        }
        let preflight = Preflight()
        let center = Foundation.NotificationCenter()
        let store = DeviceLogStore(
            storageURL: url,
            notificationCenter: center,
            preflight: preflight.run,
            isProtectedDataAvailable: { true }
        )
        #expect(await Self.waitUntil { preflight.successes.get() == 1 || preflight.calls.get() >= 2 })

        let token = "corrupt-\(corruption.rawValue)"
        var errors = 0
        for index in 0 ..< 20 {
            if await Self.logDevice(store, "\(token) \(index)") != nil { errors += 1 }
        }
        for _ in 0 ..< 5 {
            center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        }
        let stored = await store.entries(in: Self.everything).filter { $0.message.contains("\(token) ") }
        let text = try await Self.export(.all, appLog: InMemoryLogSink(), deviceLogStore: store)
        let exported = Self.occurrences(of: "\(token) ", in: Self.body(text))
        Self.restorePermissions(url)
        let moved = Self.movedAside(url)
        print(
            "STRESS: corrupt device log \(corruption.rawValue): preflights \(preflight.calls.get()) ok \(preflight.successes.get()), " +
                "moved aside \(moved.count), write errors \(errors), stored \(stored.count)/20, exported \(exported)"
        )

        #expect(moved.count <= 1)
        #expect(preflight.successes.get() <= 1)
        #expect(errors == 0)
        #expect(stored.count == 20)
        #expect(exported == 20)
    }

    @Test("Preflight rejects a device log store that would open read-only") func preflightRejectsReadOnlyStore() throws {
        let directory = try Self.makeDirectory()
        let url = directory.appendingPathComponent("logs/DeviceLog.sqlite")
        defer {
            Self.restorePermissions(url)
            try? FileManager.default.removeItem(at: directory)
        }
        try Self.corrupt(url, .readOnlyFile) { try Self.populateDeviceLog(at: $0, count: 10, start: Date()) }
        #expect(!DeviceLogStore.preflight(url))
    }

    @Test("A load failure that races an unlock does not move a healthy store aside") func unlockRaceKeepsHealthyStore() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appURL = directory.appendingPathComponent("logs/AppLog.sqlite")
        let deviceURL = directory.appendingPathComponent("logs/DeviceLog.sqlite")
        let seeded = Date().addingTimeInterval(-Self.hour)
        try Self.populateAppLog(at: appURL, count: 100, start: seeded)
        try Self.populateDeviceLog(at: deviceURL, count: 100, start: seeded)

        // First load fails as if still locked; the device unlocks before the main actor checks
        let loader = Loader { $0 == 0 }
        let preflight = Preflight { $0 == 0 }
        let appStore = AppLogStore(
            storageURL: appURL,
            notificationCenter: Foundation.NotificationCenter(),
            loadContainer: loader.run,
            isProtectedDataAvailable: { true }
        )
        let deviceStore = DeviceLogStore(
            storageURL: deviceURL,
            notificationCenter: Foundation.NotificationCenter(),
            preflight: preflight.run,
            isProtectedDataAvailable: { true }
        )
        #expect(await Self.waitUntil { loader.successes.get() == 1 && preflight.successes.get() == 1 })

        let appSeeds = await appStore.records(in: Self.everything, minimumLevel: .debug).filter { $0.message.hasPrefix("seed ") }
        let deviceSeeds = await deviceStore.entries(in: Self.everything).filter { $0.message.hasPrefix("seed ") }
        print(
            "STRESS: unlock race: app seeds \(appSeeds.count)/100 moved \(Self.movedAside(appURL).count), " +
                "device seeds \(deviceSeeds.count)/100 moved \(Self.movedAside(deviceURL).count)"
        )
        #expect(Self.movedAside(appURL).isEmpty)
        #expect(appSeeds.count == 100)
        #expect(Self.movedAside(deviceURL).isEmpty)
        #expect(deviceSeeds.count == 100)
    }

    // MARK: Protected data flapping

    @Test("1 000 protected data flips while logging open each store exactly once") func protectedDataFlapping() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appURL = directory.appendingPathComponent("logs/AppLog.sqlite")
        let deviceURL = directory.appendingPathComponent("logs/DeviceLog.sqlite")
        let locked = Box(true)
        let loader = Loader { _ in locked.get() }
        let preflight = Preflight { _ in locked.get() }
        let center = Foundation.NotificationCenter()
        let appStore = AppLogStore(
            storageURL: appURL,
            notificationCenter: center,
            loadContainer: loader.run,
            isProtectedDataAvailable: { !locked.get() }
        )
        let deviceStore = DeviceLogStore(
            storageURL: deviceURL,
            notificationCenter: center,
            preflight: preflight.run,
            isProtectedDataAvailable: { !locked.get() }
        )

        let perSource = 4000
        let start = Date()
        let producer = Task {
            for index in 0 ..< perSource {
                appStore.accept(Self.record("flap \(index)", at: start.addingTimeInterval(Double(index) / 1000)))
                deviceStore.log(
                    managerIdentifier: "com.example.pump",
                    deviceIdentifier: nil,
                    type: .send,
                    message: "flap \(index)"
                )
                if index % 100 == 0 { await Task.yield() }
            }
        }
        let clock = ContinuousClock()
        let flapTime = clock.measure {
            DispatchQueue.concurrentPerform(iterations: 1000) { index in
                let lock = index % 2 == 1
                locked.set(lock)
                let name = lock ? UIApplication.protectedDataWillBecomeUnavailableNotification : UIApplication
                    .protectedDataDidBecomeAvailableNotification
                center.post(name: name, object: nil)
            }
        }
        await producer.value
        locked.set(false)
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        #expect(await Self.waitUntil { loader.successes.get() == 1 && preflight.successes.get() == 1 })
        for _ in 0 ..< 10 {
            center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        }
        await appStore.flush()
        #expect(await Self.waitUntil(attempts: 1200) { await deviceStore.entries(in: Self.everything).count >= perSource })

        let app = await appStore.records(in: Self.everything, minimumLevel: .debug).filter { $0.message.hasPrefix("flap ") }
        let device = await deviceStore.entries(in: Self.everything).filter { $0.message.contains("flap ") }
        let deviceIndexes = device.compactMap { $0.message.split(separator: " ").last.flatMap { Int($0) } }
        print(
            "STRESS: flapping 1000 posts in \(flapTime); loads \(loader.calls.get()) ok \(loader.successes.get()), " +
                "preflights \(preflight.calls.get()) ok \(preflight.successes.get()), app \(app.count) device \(device.count)"
        )
        #expect(loader.successes.get() == 1)
        #expect(preflight.successes.get() == 1)
        #expect(Self.movedAside(appURL).count <= 1)
        #expect(Self.movedAside(deviceURL).count <= 1)
        #expect(app.map(\.message) == (0 ..< perSource).map { "flap \($0)" })
        #expect(Set(deviceIndexes) == Set(0 ..< perSource))
        #expect(deviceIndexes.count == perSource)
    }

    // MARK: Edge records

    @Test("Unusual messages round-trip through the app log store") func edgeMessagesRoundTrip() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppLogStore(
            storageURL: directory.appendingPathComponent("logs/AppLog.sqlite"),
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        let messages = [
            "",
            String(repeating: "lorem ipsum ", count: 5 * 1_048_576 / 12),
            "nul\u{0}inside\u{0}",
            "שלום עולם · مرحبا بالعالم",
            "e\u{301} \u{1F9EA}\u{200D}\u{1F52C}",
            "multi\nline\r\nmessage\u{2028}end"
        ]
        let now = Date()
        let records = messages.enumerated().map { Self.record($0.element, at: now.addingTimeInterval(Double($0.offset))) }
        records.forEach(store.accept)
        await store.flush()
        let stored = await store.records(in: Self.everything, minimumLevel: .debug)

        #expect(stored.count == records.count)
        for (original, roundTripped) in zip(records, stored) {
            // Core Data truncates strings at the first NUL, so the store replaces it
            #expect(roundTripped.message == original.message.replacingOccurrences(of: "\u{0}", with: "\u{FFFD}"))
        }
    }

    @Test("One record with a lone surrogate does not drop the rest of its batch") func loneSurrogateBatch() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppLogStore(
            storageURL: directory.appendingPathComponent("logs/AppLog.sqlite"),
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        await store.flush()
        let start = Date().addingTimeInterval(-10)
        let records = (0 ..< AppLogStore.batchSize).map { index in
            Self.record(
                index == 7 ? String(utf16CodeUnits: [0x61, 0xD800, 0x62], count: 3) : "good \(index)",
                at: start.addingTimeInterval(Double(index) / 1000)
            )
        }
        records.forEach(store.accept)
        await store.flush()
        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        print("STRESS: lone surrogate batch kept \(stored.count)/\(records.count)")
        #expect(stored.filter { $0.message.hasPrefix("good ") }.count == records.count - 1)
    }

    @Test("Edge timestamps export once each, in order, as valid UTF-8") func edgeTimestampsExport() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppLogStore(
            storageURL: directory.appendingPathComponent("logs/AppLog.sqlite"),
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        await store.flush()

        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-Self.day), end: now)
        var dated: [(String, Date)] = [
            ("", now.addingTimeInterval(-20 * Self.hour)),
            ("big " + String(repeating: "lorem ipsum ", count: 5 * 1_048_576 / 12), now.addingTimeInterval(-19 * Self.hour)),
            ("tab\tseparated", now.addingTimeInterval(-18 * Self.hour + 1)),
            ("rtl שלום مرحبا", now.addingTimeInterval(-17 * Self.hour)),
            ("multi\nline", now.addingTimeInterval(-16 * Self.hour)),
            ("future", now.addingTimeInterval(Self.day)),
            ("distant future", .distantFuture),
            ("distant past", .distantPast),
            ("epoch", Date(timeIntervalSince1970: 0)),
            ("just before window", window.start.addingTimeInterval(-0.01))
        ]
        let outside = dated.count - 5
        for (index, slice) in LogFileWriter.slices(of: window).enumerated() {
            dated.append(("boundary \(index)", slice.start))
            dated.append(("before boundary \(index)", slice.start.addingTimeInterval(-0.01)))
        }
        dated.append(("window end", window.end))
        let duplicate = now.addingTimeInterval(-3 * Self.hour)
        dated += (0 ..< 200).map { ("duplicate \($0)", duplicate) }

        var generator = SystemRandomNumberGenerator()
        let accepted = dated.shuffled(using: &generator).map { Self.record($0.0, at: $0.1) }
        accepted.forEach(store.accept)
        await store.flush()

        let url = directory.appendingPathComponent("export.txt")
        try await LogFileWriter.write(header: "Header", window: window, to: url, redactor: Redactor(exactValues: [])) { slice in
            await store.records(in: slice, minimumLevel: .debug).map(LogExport.line)
        }
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
        #expect(text != nil)

        let formatter = LogFileWriter.timestampFormatter()
        let expectedRecords = accepted.enumerated()
            .filter { window.start <= $0.element.timestamp && $0.element.timestamp <= window.end }
            .sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
            .map(\.element)
        let expected = expectedRecords.map { LogFileWriter.format(LogExport.line(for: $0), formatter: formatter) }.joined()
        let actual = Self.body(text ?? "")
        #expect(expectedRecords.count == dated.count - outside - 1)
        #expect(actual.split(separator: "\n").sorted() == expected.split(separator: "\n").sorted())
        #expect(
            actual.replacingOccurrences(of: "duplicate \\d+", with: "", options: .regularExpression) ==
                expected.replacingOccurrences(of: "duplicate \\d+", with: "", options: .regularExpression)
        )

        let duplicateOrder = actual.components(separatedBy: "\n").compactMap { line -> Int? in
            guard let range = line.range(of: "[Stress] duplicate ") else { return nil }
            return Int(line[range.upperBound...])
        }
        let acceptedOrder = accepted.compactMap { $0.message.hasPrefix("duplicate ") ? Int($0.message.dropFirst(10)) : nil }
        #expect(duplicateOrder.sorted() == Array(0 ..< 200))
        #expect(duplicateOrder == acceptedOrder)
        print("STRESS: edge export \(data.count) bytes, \(expectedRecords.count) lines")
    }

    @Test("Lone surrogates and NUL bytes still produce a valid UTF-8 file") func invalidUnicodeExport() async throws {
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-Self.hour), end: now)
        let lines = [
            LogLine(date: now.addingTimeInterval(-10), source: "Trio", text: String(utf16CodeUnits: [0x61, 0xD800], count: 2)),
            LogLine(date: now.addingTimeInterval(-9), source: "Trio", text: String(utf16CodeUnits: [0xDFFF, 0x62], count: 2)),
            LogLine(date: now.addingTimeInterval(-8), source: "Trio", text: "nul\u{0}end"),
            LogLine(date: now.addingTimeInterval(-7), source: "Trio", text: "\u{FEFF}bom \u{202E}override")
        ]
        let data = try await Self.write(lines, window: window)
        let text = String(data: data, encoding: .utf8)
        #expect(text != nil)
        #expect(Self.body(text ?? "").split(separator: "\n").count == lines.count)
    }

    @Test("Export across Europe/Berlin DST changes stays in time order") func daylightSavingExport() async throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: "Europe/Berlin"))
        defer { NSTimeZone.default = previous }

        let parser = LogFileWriter.timestampFormatter()
        let transitions: [(start: Date, repeated: String?, missing: String?)] = [
            (Date(timeIntervalSince1970: 1_774_735_200), nil, "2026-03-29 02:"),
            (Date(timeIntervalSince1970: 1_792_879_200), "2026-10-25 02:30:00.000", nil)
        ]
        for transition in transitions {
            let window = DateInterval(start: transition.start, duration: 6 * Self.hour)
            let dates = (0 ... 72).map { transition.start.addingTimeInterval(Double($0) * 5 * 60) }
            let lines = dates.reversed().map { LogLine(date: $0, source: "Trio", text: "tick") }
            let data = try await Self.write(lines, window: window)
            let body = Self.body(String(decoding: data, as: UTF8.self))
            let parsed = body.split(separator: "\n").compactMap { parser.date(from: String($0.dropLast(10))) }
            #expect(parsed == dates)
            #expect(body.contains("+0100"))
            #expect(body.contains("+0200"))
            if let repeated = transition.repeated {
                #expect(body.contains("\(repeated) +0200"))
                #expect(body.contains("\(repeated) +0100"))
            }
            if let missing = transition.missing {
                #expect(!body.contains(missing))
            }
        }
    }

    // MARK: Redaction

    @Test("Secrets never leak across 64 KB redaction batches, file edges or multi-line messages") func redactionBoundaries() async throws {
        let secret = "synthetic-secret-0001"
        let host = "my-site.example.test"
        let device = "SYN-DEV-0042"
        let hexToken = Insecure.SHA1.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
        var values = SensitiveValues()
        values.addNightscout(url: "https://\(host)/", secret: secret)
        values.add(device, .device)
        let redactor = Redactor(exactValues: values.values)
        let forms = [
            secret,
            "GET HTTPS://\(host.uppercased())/api/v1/entries.json",
            "{\"url\":\"https:\\/\\/\(host)\\/api\\/v1\"}",
            "x\(host)y glued",
            "line one\nline two \(secret)\nline three",
            "api-secret: \(hexToken)",
            "device \(device.lowercased()) ok",
            "pumpSN: \(device)",
            "ends with \(secret)"
        ]
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-Self.day), end: now)
        var lines: [LogLine] = []
        var planted = 0
        for index in 0 ..< 6000 {
            var text = "row \(index) " + String(repeating: "p", count: (index * 37) % 211)
            if index % 7 == 0 {
                text += " " + forms[index % forms.count]
                planted += 1
            }
            lines.append(LogLine(date: window.start.addingTimeInterval(Double(index) * 14), source: "Trio", text: text))
        }
        let filler = String(repeating: "lorem ipsum ", count: 20000)
        lines
            .append(LogLine(
                date: now.addingTimeInterval(-60),
                source: "Trio",
                text: "\(secret) \(filler)\(host) \(filler)\(secret)"
            ))
        lines.append(LogLine(date: now, source: "Trio", text: "last \(secret)"))

        let clock = ContinuousClock()
        var data = Data()
        let elapsed = try await clock.measure {
            data = try await Self.write(lines, window: window, header: "\(secret) header \(host)", redactor: redactor)
        }
        let text = String(decoding: data, as: UTF8.self).lowercased()
        print("STRESS: redaction \(data.count) bytes, \(planted) planted in \(elapsed)")
        for value in [secret, host, device, hexToken] {
            #expect(!text.contains(value.lowercased()), "\(value) leaked")
        }
        #expect(text.hasPrefix("<api-secret> header <nightscout-host>"))
        #expect(text.hasSuffix("last <api-secret>\n"))
    }

    @Test(
        "Encoded and case-shifted secrets are redacted",
        arguments: [
            ("percent-encoded secret", "token=synthetic%20secret%2F0001%21 sent", "synthetic%20secret%2f0001%21"),
            ("form-encoded secret", "body secret=synthetic+secret%2F0001%21", "synthetic+secret%2f0001%21"),
            ("uppercase secret", "secret SYNTHETIC SECRET/0001! set", "synthetic secret/0001!"),
            ("uppercase scheme and host", "GET HTTPS://MY-SITE.EXAMPLE.TEST/api/v1", "my-site.example.test"),
            ("encoded URL", "next=https%3A%2F%2Fmy-site.example.test%2Fapi", "my-site.example.test")
        ]
    ) func encodedVariants(name _: String, input: String, leaked: String) {
        var values = SensitiveValues()
        values.addNightscout(url: "https://my-site.example.test", secret: "synthetic secret/0001!")
        let output = Redactor(exactValues: values.values).redact(input).lowercased()
        #expect(!output.contains(leaked), "\(output)")
    }

    @Test("Thousands of distinct serials get stable, unique placeholders") func manySerials() {
        let devices = (0 ..< 200).map { String(format: "SYN-DEV-%04d", $0) }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let serials = (0 ..< 5000).map { index -> String in
            var value = index
            var characters: [Character] = []
            for _ in 0 ..< 4 {
                characters.append(alphabet[value % alphabet.count])
                value /= alphabet.count
            }
            return "8G" + String(characters)
        }
        let redactor = Redactor(
            exactValues: devices.map { Redactor.ExactValue(value: $0, kind: .device) }
                + serials.map { Redactor.ExactValue(value: $0, kind: .cgmSerial) }
        )
        let first = serials.enumerated().map {
            redactor.redact("transmitterID: \($0.element) device \(devices[$0.offset % devices.count])")
        }
        let placeholders = first.map { line -> String in
            String(line.dropFirst("transmitterID: ".count).prefix { $0 != " " })
        }
        #expect(placeholders == (1 ... 5000).map { "<cgm-serial-\($0)>" })
        #expect(first.allSatisfy { !$0.contains("SYN-DEV") })
        #expect(Set(first.map { String($0.split(separator: " ").last ?? "") }).count == devices.count)

        var generator = SystemRandomNumberGenerator()
        for index in Array(serials.indices).shuffled(using: &generator).prefix(1000) {
            #expect(redactor.redact("transmitterID: \(serials[index])") == "transmitterID: \(placeholders[index])")
        }
    }

    @Test(
        "Clinical numbers, dates, UUIDs and plugin identifiers are not redacted",
        arguments: [
            "BG 123 mg/dL, delta -4, eventual 98",
            "IOB 1.25 U, COB 23 g, ISF 2.8 mmol/L/U, CR 1:10",
            "rate 0.85 U/h for 30 min, SMB 0.3 U",
            "2026-10-18T12:00:00.000Z → 2026-10-18 14:00:00.000 +0200",
            "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
            "com.loopkit.OmnipodKit org.nightscout.MedtrumKit org.loopkit.G7SensorKit",
            "DexG6Transmitter G7CGMManager LibreTransmitterManagerV3 DanaKit",
            "Transmitter battery low",
            "glucose 5.5 mmol/L at 14:05, trend ↗︎",
            "version 1.0.2.2 build 20261019"
        ]
    ) func noFalsePositives(input: String) {
        #expect(Redactor(exactValues: []).redact(input) == input)
    }

    @Test(
        "Six-letter words after Transmitter are not treated as serials",
        arguments: ["Transmitter paired", "Transmitter failed", "transmitter status ok", "TID search started"]
    ) func transmitterWords(input: String) {
        let redactor = Redactor(exactValues: [Redactor.ExactValue(value: "8GABCD", kind: .cgmSerial)])
        #expect(redactor.redact(input) == input)
    }

    @Test("Long unbroken runs redact in linear time") func longRunsScale() {
        let clock = ContinuousClock()
        let timings = [8192, 16384, 32768].map { size -> (Int, Double) in
            let run = String(repeating: "a1", count: size / 2)
            let redactor = Redactor(exactValues: LoggingStressFixtures.storedValues.values)
            return (size, clock.measure { _ = redactor.redact(run) }.seconds)
        }
        let spaced = String(repeating: "lorem ipsum ", count: 5 * 1_048_576 / 12)
        let spacedTime = clock.measure { _ = Redactor(exactValues: LoggingStressFixtures.storedValues.values).redact(spaced) }
        let ratio = timings[2].1 / max(timings[0].1, 0.000_001)
        let runs = timings.map { "\($0.0) B \(String(format: "%.3f", $0.1)) s" }.joined(separator: ", ")
        print(
            "STRESS: unbroken run redaction \(runs); 4x size -> \(String(format: "%.1f", ratio))x time; " +
                "5 MB spaced text \(spacedTime)"
        )
        #expect(ratio < 8)
    }

    // MARK: Export lifecycle

    @Test("Concurrent, cancelled, empty and failing exports leave no temporary directories") func exportLifecycle() async throws {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
        func exportDirectories() -> Set<String> {
            Set(((try? fileManager.contentsOfDirectory(atPath: temporary.path)) ?? []).filter { UUID(uuidString: $0) != nil })
        }
        let fixture = try Self.makeDirectory()
        defer { try? fileManager.removeItem(at: fixture) }
        let deviceStore = DeviceLogStore(
            storageURL: fixture.appendingPathComponent("logs/DeviceLog.sqlite"),
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        for index in 0 ..< 200 {
            let manager = index.isMultiple(of: 2) ? "com.example.pump" : "com.example.cgm"
            await Self.logDevice(deviceStore, "entry \(index)", manager: manager, device: "SYN-DEV-0042")
        }
        let sink = InMemoryLogSink(capacity: 120_000)
        let now = Date()
        for index in 0 ..< 100_000 {
            sink
                .accept(
                    Self
                        .record(
                            "history \(index) transmitterID: 8GAB\(index % 10)C",
                            at: now.addingTimeInterval(-Double(index) * 6)
                        )
                )
        }
        let before = exportDirectories()
        let export = LogExport(appLog: sink, deviceLogStore: deviceStore, pump: StubManager(), cgm: StubCGMManager())

        let clock = ContinuousClock()
        var files: [URL] = []
        let concurrentTime = await clock.measure {
            files = await withTaskGroup(of: URL?.self) { group in
                for (kind, days) in [(LogExport.Kind.all, 7), (.pump, 7), (.cgm, 7), (.all, 1), (.pump, 3)] {
                    group.addTask { try? await export.makeFile(kind, days: days) }
                }
                group.addTask {
                    for index in 0 ..< 5000 {
                        sink.accept(Self.record("live \(index)", at: Date()))
                    }
                    return nil
                }
                return await group.reduce(into: []) { files, file in
                    if let file { files.append(file) }
                }
            }
        }
        #expect(files.count == 5)
        #expect(Set(files.map { $0.deletingLastPathComponent() }).count == 5)
        for file in files {
            #expect(try Data(contentsOf: file).prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
            LogExport.discard(file)
        }

        var cancelOutcomes: [String] = []
        for delay in [0, 5, 20, 80] as [UInt64] {
            let task = Task { try await export.makeFile(.all, days: 7) }
            try? await Task.sleep(nanoseconds: delay * 1_000_000)
            task.cancel()
            let cancelled = clock.now
            switch await task.result {
            case let .success(file):
                cancelOutcomes.append("\(delay) ms: finished")
                LogExport.discard(file)
            case let .failure(failure):
                cancelOutcomes.append("\(delay) ms: \(type(of: failure)) after \(clock.now - cancelled)")
                #expect(failure is CancellationError, "\(delay) ms")
            }
        }
        #expect(cancelOutcomes.allSatisfy { !$0.hasSuffix("finished") }, "\(cancelOutcomes)")

        let emptyStore = DeviceLogStore(
            storageURL: fixture.appendingPathComponent("empty/DeviceLog.sqlite"),
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        let emptyFile = try await LogExport(appLog: InMemoryLogSink(), deviceLogStore: emptyStore, pump: nil, cgm: nil)
            .makeFile(.all, days: 1)
        #expect(fileManager.fileExists(atPath: emptyFile.path))
        LogExport.discard(emptyFile)

        let permissions = try fileManager.attributesOfItem(atPath: temporary.path)[.posixPermissions] as? Int ?? 0o755
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: temporary.path)
        var failedCleanly = false
        do {
            let file = try await export.makeFile(.cgm, days: 1)
            LogExport.discard(file)
        } catch {
            failedCleanly = true
        }
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
        #expect(failedCleanly)

        let leftovers = exportDirectories().subtracting(before)
        print(
            "STRESS: 5 concurrent exports in \(concurrentTime); cancel outcomes \(cancelOutcomes); leftovers \(leftovers.count)"
        )
        #expect(leftovers.isEmpty)
    }

    // MARK: Retention

    @Test("Changing retention during heavy logging purges and drops debug records") func retentionChangeUnderLoad() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("logs/AppLog.sqlite")
        let now = Date()
        try Self.populateAppLog(at: url, count: 7 * 24 * 60, start: now.addingTimeInterval(-7 * Self.day + 60), step: 60)
        let store = AppLogStore(
            storageURL: url,
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        await store.flush()
        let seeded = await store.records(in: Self.everything, minimumLevel: .debug).count

        let counter = Box(0)
        let running = Box(true)
        let producers = (0 ..< 8).map { _ in
            Task.detached {
                while running.get() {
                    let index = counter.update { value -> Int in
                        value += 1
                        return value
                    }
                    store.accept(Self.record("load \(index)", at: Date(), level: index.isMultiple(of: 2) ? .debug : .info))
                    if index % 64 == 0 { await Task.yield() }
                }
            }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        var policy = LogRetentionPolicy.default
        policy.maxAge = Self.day
        policy.persistsDebug = false
        store.apply(policy)
        let applied = counter.get()
        try await Task.sleep(nanoseconds: 300_000_000)

        let clock = ContinuousClock()
        let flipTime = clock.measure {
            for flip in 0 ..< 1000 {
                var flipped = policy
                flipped.maxAge = flip.isMultiple(of: 2) ? Self.day + 60 : Self.day
                store.apply(flipped)
            }
            store.apply(policy)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        running.set(false)
        for producer in producers { await producer.value }
        await store.flush()
        let produced = counter.get()

        let stored = await store.records(in: Self.everything, minimumLevel: .debug)
        let seeds = stored.filter { $0.message.hasPrefix("seed ") }
        let lateDebug = stored.filter { record in
            guard record.level == .debug, record.message.hasPrefix("load "), let index = Int(record.message.dropFirst(5)) else {
                return false
            }
            return index > applied
        }
        print(
            "STRESS: retention seeded \(seeded), kept \(seeds.count) seeds, produced \(produced), " +
                "stored \(stored.count - seeds.count), 1000 policy flips in \(flipTime)"
        )
        #expect(seeds.allSatisfy { $0.timestamp >= now.addingTimeInterval(-Self.day - 120) })
        #expect(seeds.count >= 24 * 60 - 5 && seeds.count <= 24 * 60 + 1)
        #expect(lateDebug.isEmpty)

        policy.persistsDebug = true
        store.apply(policy)
        store.accept(Self.record("debug again", at: Date(), level: .debug))
        await store.flush()
        #expect(await store.records(in: Self.everything, minimumLevel: .debug).contains { $0.message == "debug again" })
    }
}
