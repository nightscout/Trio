import CoreData
import Foundation
import os
import UIKit

final class AppLogStore: LogSink, @unchecked Sendable {
    static let shared = AppLogStore()

    static let bufferLimit = 5000
    static let batchSize = 200
    static let flushDelay: TimeInterval = 2
    static let purgeInterval: TimeInterval = 24 * 60 * 60
    static let legacyFileMaxAge: TimeInterval = 7 * 24 * 60 * 60

    private static let entityName = "AppLogEntry"
    private static let model: NSManagedObjectModel? = Bundle.main.url(forResource: "AppLog", withExtension: "momd")
        .flatMap { NSManagedObjectModel(contentsOf: $0) }

    private struct Pending: Sendable {
        var records: [LogRecord] = []
        var persistsDebug: Bool
        var flushScheduled = false
        var batchFlushScheduled = false
    }

    let storageURL: URL
    var directory: URL { storageURL.deletingLastPathComponent() }

    private let pending: OSAllocatedUnfairLock<Pending>
    private let queue = DispatchQueue(label: "AppLogStore.queue", qos: .utility)
    private let notificationCenter: Foundation.NotificationCenter
    private let loadContainer: (URL) -> NSPersistentContainer?
    private let isProtectedDataAvailable: @MainActor() -> Bool
    private var observers: [NSObjectProtocol] = []

    // Confined to `queue`
    private var container: NSPersistentContainer?
    private var context: NSManagedObjectContext?
    private var policy: LogRetentionPolicy
    private var lastPurge: Date?
    private var isCheckingProtectedData = false
    private var didMoveStoreAside = false
    private var didReopenAfterFailure = false

    init(
        storageURL: URL = AppLogStore.defaultStorageURL,
        policy: LogRetentionPolicy = .default,
        notificationCenter: Foundation.NotificationCenter = .default,
        loadContainer: @escaping (URL) -> NSPersistentContainer? = AppLogStore.loadContainer,
        isProtectedDataAvailable: @escaping @MainActor() -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    ) {
        self.storageURL = storageURL
        self.policy = policy
        self.notificationCenter = notificationCenter
        self.loadContainer = loadContainer
        self.isProtectedDataAvailable = isProtectedDataAvailable
        pending = OSAllocatedUnfairLock(initialState: Pending(persistsDebug: policy.persistsDebug))

        observers = [
            notificationCenter.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.openIfNeeded() }
            },
            notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.flushPending() }
            },
            notificationCenter.addObserver(
                forName: UIApplication.willTerminateNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.queue.sync { self?.flushPending() }
            }
        ]
        queue.async { self.openIfNeeded() }
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    static var defaultStorageURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            // Shares the legacy lowercase directory; a sibling "Logs" collides on case-insensitive volumes
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("AppLog.sqlite")
    }

    func accept(_ record: LogRecord) {
        let (scheduleDelayed, flushNow) = pending.withLock { state -> (Bool, Bool) in
            guard record.level != .debug || state.persistsDebug else { return (false, false) }
            state.records.append(record)
            if state.records.count > Self.bufferLimit {
                // Drop a chunk so a full buffer doesn't shift on every record
                state.records.removeFirst(state.records.count - Self.bufferLimit + Self.bufferLimit / 10)
            }
            let scheduleDelayed = !state.flushScheduled
            state.flushScheduled = true
            let flushNow = state.records.count >= Self.batchSize && !state.batchFlushScheduled
            if flushNow { state.batchFlushScheduled = true }
            return (scheduleDelayed, flushNow)
        }
        if flushNow {
            queue.async { self.flushPending() }
        }
        if scheduleDelayed {
            queue.asyncAfter(deadline: .now() + Self.flushDelay) {
                self.pending.withLock { $0.flushScheduled = false }
                self.flushPending()
            }
        }
    }

    // Exports wait on these, so they run ahead of background logging load
    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async(qos: .userInitiated, flags: .enforceQoS) {
                self.flushPending()
                continuation.resume()
            }
        }
    }

    func records(in window: DateInterval, minimumLevel: LogLevel) async -> [LogRecord] {
        await withCheckedContinuation { continuation in
            queue.async(qos: .userInitiated, flags: .enforceQoS) {
                self.flushPending()
                continuation.resume(returning: self.fetch(in: window, minimumLevel: minimumLevel))
            }
        }
    }

    func apply(_ policy: LogRetentionPolicy) {
        pending.withLock { $0.persistsDebug = policy.persistsDebug }
        queue.async {
            guard self.policy != policy else { return }
            self.policy = policy
            self.purge()
        }
    }

    func observeSettings(of settingsManager: SettingsManager, broadcaster: Broadcaster) {
        apply(LogRetentionPolicy(settings: settingsManager.settings))
        broadcaster.register(SettingsObserver.self, observer: self)
    }

    private func flushPending() {
        guard let context else { return }
        let batch = pending.withLock { state -> [LogRecord] in
            defer {
                state.records.removeAll(keepingCapacity: true)
                state.batchFlushScheduled = false
            }
            return state.records
        }
        let unsaved = batch.isEmpty ? [] : insert(batch[...], into: context)
        guard unsaved.isEmpty else {
            storeFailed(keeping: unsaved)
            return
        }
        if let lastPurge, Date().timeIntervalSince(lastPurge) < Self.purgeInterval { return }
        purge()
    }

    // Returns the records the store itself failed to take; records it rejects are dropped one by one
    private func insert(_ batch: ArraySlice<LogRecord>, into context: NSManagedObjectContext) -> ArraySlice<LogRecord> {
        var iterator = batch.makeIterator()
        let request = NSBatchInsertRequest(entityName: Self.entityName, dictionaryHandler: { dictionary in
            guard let record = iterator.next() else { return true }
            dictionary.addEntries(from: [
                "timestamp": record.timestamp,
                "level": record.level.rawValue,
                "category": Self.sanitized(record.category),
                "message": Self.sanitized(record.message),
                "file": Self.sanitized(record.file),
                "function": Self.sanitized(record.function),
                "line": Int32(clamping: record.line),
                "launchID": record.launchID
            ])
            return false
        })
        do {
            try context.performAndWait { _ = try context.execute(request) }
            return []
        } catch {
            if Self.isStoreFailure(error) {
                Logger.Category.storage.osLogger.error("App log insert failed: \(String(describing: error), privacy: .public)")
                return batch
            }
            guard batch.count > 1 else {
                Logger.Category.storage.osLogger.fault("App log record dropped: \(String(describing: error), privacy: .public)")
                return []
            }
            let middle = batch.startIndex + batch.count / 2
            let unsaved = insert(batch[..<middle], into: context)
            guard unsaved.isEmpty else { return unsaved + batch[middle...] }
            return insert(batch[middle...], into: context)
        }
    }

    private static func sanitized(_ string: String) -> String {
        // Native Swift strings are valid UTF-8, so this also repairs lone surrogates from bridged strings
        var string = string
        string.makeContiguousUTF8()
        guard string.utf8.contains(0) else { return string }
        return string.replacingOccurrences(of: "\u{0}", with: "\u{FFFD}")
    }

    private static func isStoreFailure(_ error: Error) -> Bool {
        let error = error as NSError
        let code = error.domain == NSSQLiteErrorDomain ? error.code : error.userInfo[NSSQLiteErrorDomain] as? Int
        // SQLITE_READONLY, IOERR, CORRUPT, FULL, CANTOPEN, NOTADB
        return code.map { [8, 10, 11, 13, 14, 26].contains($0 & 0xFF) } ?? false
    }

    private func fetch(in window: DateInterval, minimumLevel: LogLevel) -> [LogRecord] {
        guard let context else {
            return pending.withLock { $0.records }
                .filter { window.contains($0.timestamp) && $0.level >= minimumLevel }
        }
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = Self.fetchedProperties
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@ AND level >= %d",
            window.start as NSDate,
            window.end as NSDate,
            minimumLevel.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        let rows = context.performAndWait { (try? context.fetch(request)) ?? [] }
        var fetched: [(record: LogRecord, objectID: NSManagedObjectID?)] = rows.compactMap { row in
            guard let timestamp = row["timestamp"] as? Date,
                  let level = (row["level"] as? Int16).flatMap(LogLevel.init(rawValue:))
            else { return nil }
            let record = LogRecord(
                timestamp: timestamp,
                level: level,
                category: row["category"] as? String ?? "",
                message: row["message"] as? String ?? "",
                file: row["file"] as? String ?? "",
                function: row["function"] as? String ?? "",
                line: UInt(max(0, row["line"] as? Int32 ?? 0)),
                launchID: row["launchID"] as? UUID ?? UUID()
            )
            return (record, row["objectID"] as? NSManagedObjectID)
        }
        Self.sortTiesByInsertion(&fetched)
        return fetched.map(\.record)
    }

    private static let fetchedProperties: [Any] = {
        let objectID = NSExpressionDescription()
        objectID.name = "objectID"
        objectID.expression = NSExpression.expressionForEvaluatedObject()
        objectID.expressionResultType = .objectIDAttributeType
        return ["timestamp", "level", "category", "message", "file", "function", "line", "launchID", objectID]
    }()

    // SQLite returns equal timestamps in no particular order; primary keys follow insertion
    private static func sortTiesByInsertion(_ rows: inout [(record: LogRecord, objectID: NSManagedObjectID?)]) {
        var start = 0
        while start < rows.count {
            var end = start + 1
            while end < rows.count, rows[end].record.timestamp == rows[start].record.timestamp {
                end += 1
            }
            if end - start > 1 {
                let ordered = rows[start ..< end].map { (insertionOrder($0.objectID), $0) }.sorted { $0.0 < $1.0 }
                rows.replaceSubrange(start ..< end, with: ordered.map(\.1))
            }
            start = end
        }
    }

    private static func insertionOrder(_ objectID: NSManagedObjectID?) -> Int {
        // Permanent IDs end in "p<primary key>"
        objectID.flatMap { Int($0.uriRepresentation().lastPathComponent.dropFirst()) } ?? Int.max
    }

    private func purge() {
        guard let context else { return }
        lastPurge = Date()
        let maxAge = policy.maxAge
        let maxRows = policy.maxRows
        context.performAndWait {
            deleteEntries(before: Date().addingTimeInterval(-maxAge), in: context)

            let newest = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
            newest.resultType = .dictionaryResultType
            newest.propertiesToFetch = ["timestamp"]
            newest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            newest.fetchOffset = max(0, maxRows - 1)
            newest.fetchLimit = 1
            if let cutoff = (try? context.fetch(newest))?.first?["timestamp"] as? Date {
                deleteEntries(before: cutoff, in: context)
            }
        }
    }

    private func deleteEntries(before date: Date, in context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        request.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        } catch {
            Logger.Category.storage.osLogger.error("App log purge failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func openIfNeeded() {
        guard container == nil, !isCheckingProtectedData else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let container = loadContainer(storageURL) {
            open(container)
            return
        }
        // A locked device also fails to load; only move the store aside once data is readable
        isCheckingProtectedData = true
        Task { @MainActor in
            let available = self.isProtectedDataAvailable()
            self.queue.async {
                self.isCheckingProtectedData = false
                self.recover(protectedDataAvailable: available)
            }
        }
    }

    private func recover(protectedDataAvailable: Bool) {
        guard container == nil, protectedDataAvailable, !didMoveStoreAside else { return }
        // The first attempt may have raced an unlock
        if let container = loadContainer(storageURL) {
            open(container)
            return
        }
        didMoveStoreAside = true
        moveStoreAside()
        if let container = loadContainer(storageURL) {
            open(container)
        } else {
            Logger.Category.storage.osLogger.error("App log store unavailable, keeping records in memory")
        }
    }

    private func storeFailed(keeping unsaved: ArraySlice<LogRecord>) {
        pending.withLock { state in
            state.records.insert(contentsOf: unsaved, at: 0)
            if state.records.count > Self.bufferLimit {
                state.records.removeFirst(state.records.count - Self.bufferLimit)
            }
        }
        if let coordinator = container?.persistentStoreCoordinator {
            for store in coordinator.persistentStores {
                try? coordinator.remove(store)
            }
        }
        container = nil
        context = nil
        guard !didReopenAfterFailure else {
            Logger.Category.storage.osLogger.error("App log store unavailable, keeping records in memory")
            return
        }
        didReopenAfterFailure = true
        openIfNeeded()
    }

    private func open(_ container: NSPersistentContainer) {
        self.container = container
        let context = container.newBackgroundContext()
        context.undoManager = nil
        self.context = context
        deleteLegacyFiles()
        FileManager.default.removeUnreadableStores(of: storageURL)
        flushPending()
    }

    private func moveStoreAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storageURL.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: source.path + ".unreadable-\(stamp)")
            do {
                try FileManager.default.moveItem(at: source, to: destination)
            } catch {
                Logger.Category.storage.osLogger
                    .error("Could not move app log file aside: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func deleteLegacyFiles() {
        let cutoff = Date().addingTimeInterval(-Self.legacyFileMaxAge)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files where file.pathExtension == "txt" {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func loadContainer(_ url: URL) -> NSPersistentContainer? {
        guard let model, FileManager.default.isWritableStore(at: url) else { return nil }
        let container = NSPersistentContainer(name: "AppLog", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        let coordinator = container.persistentStoreCoordinator
        guard loadError == nil, !coordinator.persistentStores.contains(where: \.isReadOnly) else {
            for store in coordinator.persistentStores {
                try? coordinator.remove(store)
            }
            return nil
        }
        return container
    }
}

extension AppLogStore: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        apply(LogRetentionPolicy(settings: settings))
    }
}

extension LogRetentionPolicy {
    init(settings: TrioSettings) {
        self.init(
            maxAge: TimeInterval(max(1, settings.logRetentionDays)) * 24 * 60 * 60,
            persistsDebug: settings.logVerboseEnabled,
            maxRows: LogRetentionPolicy.default.maxRows
        )
    }
}

extension AppLogStore {
    private static let watchTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    static func watchRecords(from payload: String, receivedAt date: Date = Date()) -> [LogRecord] {
        payload.split(whereSeparator: \.isNewline).compactMap { line in
            var message = line.trimmingCharacters(in: .whitespaces)
            guard !message.isEmpty else { return nil }
            var timestamp = date
            if message.hasPrefix("["), let close = message.firstIndex(of: "]"),
               let parsed = watchTimestampFormatter
               .date(from: String(message[message.index(after: message.startIndex) ..< close]))
            {
                timestamp = parsed
                message = message[message.index(after: close)...].trimmingCharacters(in: .whitespaces)
            }
            return LogRecord(
                timestamp: timestamp,
                level: .debug,
                category: "Watch",
                message: message,
                file: "WatchLogger",
                function: "",
                line: 0,
                launchID: LaunchID.current
            )
        }
    }
}
