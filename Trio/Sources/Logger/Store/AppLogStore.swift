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

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.flushPending()
                continuation.resume()
            }
        }
    }

    func records(in window: DateInterval, minimumLevel: LogLevel) async -> [LogRecord] {
        await withCheckedContinuation { continuation in
            queue.async {
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
        if !batch.isEmpty {
            insert(batch, into: context)
        }
        if let lastPurge, Date().timeIntervalSince(lastPurge) < Self.purgeInterval { return }
        purge()
    }

    private func insert(_ batch: [LogRecord], into context: NSManagedObjectContext) {
        var iterator = batch.makeIterator()
        let request = NSBatchInsertRequest(entityName: Self.entityName, dictionaryHandler: { dictionary in
            guard let record = iterator.next() else { return true }
            dictionary.addEntries(from: [
                "timestamp": record.timestamp,
                "level": record.level.rawValue,
                "category": record.category,
                "message": record.message,
                "file": record.file,
                "function": record.function,
                "line": Int32(clamping: record.line),
                "launchID": record.launchID
            ])
            return false
        })
        context.performAndWait {
            do {
                try context.execute(request)
            } catch {
                Logger.Category.coreData.osLogger.error("App log insert failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func fetch(in window: DateInterval, minimumLevel: LogLevel) -> [LogRecord] {
        guard let context else {
            return pending.withLock { $0.records }
                .filter { window.contains($0.timestamp) && $0.level >= minimumLevel }
        }
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@ AND level >= %d",
            window.start as NSDate,
            window.end as NSDate,
            minimumLevel.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return context.performAndWait {
            let rows = (try? context.fetch(request)) ?? []
            return rows.compactMap { row in
                guard let timestamp = row["timestamp"] as? Date,
                      let level = (row["level"] as? Int16).flatMap(LogLevel.init(rawValue:))
                else { return nil }
                return LogRecord(
                    timestamp: timestamp,
                    level: level,
                    category: row["category"] as? String ?? "",
                    message: row["message"] as? String ?? "",
                    file: row["file"] as? String ?? "",
                    function: row["function"] as? String ?? "",
                    line: UInt(max(0, row["line"] as? Int32 ?? 0)),
                    launchID: row["launchID"] as? UUID ?? UUID()
                )
            }
        }
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
            Logger.Category.coreData.osLogger.error("App log purge failed: \(String(describing: error), privacy: .public)")
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
        didMoveStoreAside = true
        moveStoreAside()
        if let container = loadContainer(storageURL) {
            open(container)
        } else {
            Logger.Category.coreData.osLogger.error("App log store unavailable, keeping records in memory")
        }
    }

    private func open(_ container: NSPersistentContainer) {
        self.container = container
        let context = container.newBackgroundContext()
        context.undoManager = nil
        self.context = context
        deleteLegacyFiles()
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
                Logger.Category.coreData.osLogger
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
        guard let model else { return nil }
        let container = NSPersistentContainer(name: "AppLog", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        guard loadError == nil else {
            let coordinator = container.persistentStoreCoordinator
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
