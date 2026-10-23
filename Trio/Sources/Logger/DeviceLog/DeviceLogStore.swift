import CoreData
import Foundation
import LoopKit
import UIKit

final class DeviceLogStore: @unchecked Sendable {
    static let bufferLimit = 5000

    private struct PendingEntry {
        let managerIdentifier: String
        let deviceIdentifier: String?
        let type: DeviceLogEntryType
        let message: String
        let date: Date
    }

    private static let queuedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let queue = DispatchQueue(label: "DeviceLogStore.queue", qos: .utility)
    private let storageURL: URL
    private let maxAge: TimeInterval
    private let notificationCenter: Foundation.NotificationCenter
    private let preflight: (URL) -> Bool
    private let isProtectedDataAvailable: @MainActor() -> Bool
    private var observer: NSObjectProtocol?

    // Confined to `queue`
    private var deviceLog: PersistentDeviceLog?
    private var buffer: [PendingEntry] = []
    private var isCheckingProtectedData = false
    private var retryAfterCheck = false
    private var didMoveStoreAside = false

    init(
        storageURL: URL = DeviceLogStore.defaultStorageURL,
        maxAge: TimeInterval = LogRetentionPolicy.default.maxAge,
        notificationCenter: Foundation.NotificationCenter = .default,
        preflight: @escaping (URL) -> Bool = DeviceLogStore.preflight,
        isProtectedDataAvailable: @escaping @MainActor() -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    ) {
        self.storageURL = storageURL
        self.maxAge = maxAge
        self.notificationCenter = notificationCenter
        self.preflight = preflight
        self.isProtectedDataAvailable = isProtectedDataAvailable

        observer = notificationCenter.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.openIfNeeded() }
        }
        queue.async { self.openIfNeeded() }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    static var defaultStorageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            // Shares the legacy lowercase directory; a sibling "Logs" collides on case-insensitive volumes
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("DeviceLog.sqlite")
    }

    func log(
        managerIdentifier: String,
        deviceIdentifier: String?,
        type: DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        let date = Date()
        queue.async {
            if let deviceLog = self.deviceLog {
                deviceLog.log(
                    managerIdentifier: managerIdentifier,
                    deviceIdentifier: deviceIdentifier,
                    type: type,
                    message: message,
                    completion: completion
                )
                return
            }
            self.buffer.append(PendingEntry(
                managerIdentifier: managerIdentifier,
                deviceIdentifier: deviceIdentifier,
                type: type,
                message: message,
                date: date
            ))
            if self.buffer.count > Self.bufferLimit {
                self.buffer.removeFirst(self.buffer.count - Self.bufferLimit)
            }
            completion?(nil)
        }
    }

    func entries(in window: DateInterval, managerIdentifier: String? = nil) async -> [StoredDeviceLogEntry] {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let deviceLog = self.deviceLog else {
                    continuation.resume(returning: self.buffer.compactMap { entry in
                        guard window.contains(entry.date),
                              managerIdentifier == nil || entry.managerIdentifier == managerIdentifier
                        else { return nil }
                        return StoredDeviceLogEntry(
                            type: entry.type,
                            managerIdentifier: entry.managerIdentifier,
                            deviceIdentifier: entry.deviceIdentifier,
                            message: entry.message,
                            timestamp: entry.date
                        )
                    })
                    return
                }
                deviceLog.getLogEntries(startDate: window.start, endDate: window.end) { result in
                    let entries = (try? result.get()) ?? []
                    guard let managerIdentifier else {
                        continuation.resume(returning: entries)
                        return
                    }
                    continuation.resume(returning: entries.filter { $0.managerIdentifier == managerIdentifier })
                }
            }
        }
    }

    private func openIfNeeded() {
        guard deviceLog == nil else { return }
        // An unlock during the check must not be lost
        guard !isCheckingProtectedData else {
            retryAfterCheck = true
            return
        }
        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if preflight(storageURL) {
            open()
            return
        }
        // A locked device also fails to load; only move the store aside once data is readable
        isCheckingProtectedData = true
        Task { @MainActor in
            let available = self.isProtectedDataAvailable()
            self.queue.async {
                self.isCheckingProtectedData = false
                self.recover(protectedDataAvailable: available)
                if self.retryAfterCheck {
                    self.retryAfterCheck = false
                    self.openIfNeeded()
                }
            }
        }
    }

    private func recover(protectedDataAvailable: Bool) {
        guard deviceLog == nil, protectedDataAvailable, !didMoveStoreAside else { return }
        // The first attempt may have raced an unlock
        if preflight(storageURL) {
            open()
            return
        }
        didMoveStoreAside = true
        moveStoreAside()
        if preflight(storageURL) {
            open()
        } else {
            warning(.storage, "Device log store unavailable, keeping entries in memory")
        }
    }

    private func open() {
        let deviceLog = PersistentDeviceLog(storageFile: storageURL, maxEntryAge: maxAge)
        self.deviceLog = deviceLog
        for entry in buffer {
            deviceLog.log(
                managerIdentifier: entry.managerIdentifier,
                deviceIdentifier: entry.deviceIdentifier,
                type: entry.type,
                message: "[queued \(Self.queuedDateFormatter.string(from: entry.date))] \(entry.message)"
            )
        }
        buffer.removeAll()
        deviceLog.purgeLogEntries(before: Date().addingTimeInterval(-maxAge))
        FileManager.default.removeUnreadableStores(of: storageURL)
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
                warning(.storage, "Moving unreadable device log aside failed", error: error)
            }
        }
    }

    static func preflight(_ url: URL) -> Bool {
        guard FileManager.default.isWritableStore(at: url) else { return false }
        return autoreleasepool {
            guard let modelURL = Bundle(for: PersistentDeviceLog.self).url(forResource: "DeviceLog", withExtension: "momd"),
                  let model = NSManagedObjectModel(contentsOf: modelURL)
            else { return false }
            let container = NSPersistentContainer(name: "DeviceLog", managedObjectModel: model)
            let description = NSPersistentStoreDescription(url: url)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            let coordinator = container.persistentStoreCoordinator
            let isReadOnly = coordinator.persistentStores.contains(where: \.isReadOnly)
            for store in coordinator.persistentStores {
                try? coordinator.remove(store)
            }
            return loadError == nil && !isReadOnly
        }
    }
}

extension FileManager {
    static let unreadableStoreMaxAge: TimeInterval = 7 * 24 * 60 * 60

    // Stores moved aside as "<name>.unreadable-<epoch>"
    func removeUnreadableStores(of url: URL) {
        let directory = url.deletingLastPathComponent()
        let names = (try? contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(url.lastPathComponent) {
            guard let marker = name.range(of: ".unreadable-", options: .backwards),
                  let stamp = TimeInterval(name[marker.upperBound...]),
                  Date().timeIntervalSince1970 - stamp > Self.unreadableStoreMaxAge
            else { continue }
            try? removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func isWritableStore(at url: URL) -> Bool {
        guard isWritableFile(atPath: url.deletingLastPathComponent().path) else { return false }
        return ["", "-wal", "-shm"].allSatisfy { suffix in
            !fileExists(atPath: url.path + suffix) || isWritableFile(atPath: url.path + suffix)
        }
    }
}
