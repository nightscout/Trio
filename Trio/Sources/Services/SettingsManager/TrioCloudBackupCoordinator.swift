import CloudKit
import Foundation
import Swinject

/// Compares configuration every 24 hours, catching up on launch or foreground after suspension.
/// Snapshots include Dynamic ISF history; the comparison fingerprint excludes it.
@MainActor final class TrioCloudBackupCoordinator {
    static let shared = TrioCloudBackupCoordinator()
    static let uploadNotification = Notification.Name("trioCloudBackupUploaded")
    static let changesNotification = Notification.Name("trioCloudBackupsChanged")
    static let retentionChoices = [3, 5, 10, 15]
    static let checkInterval: TimeInterval = 24 * 60 * 60

    private enum Keys {
        static let manualRetention = "trio.cloudBackup.manualRetention"
        static let automaticRetention = "trio.cloudBackup.automaticRetention"
        static let retentionPending = "trio.cloudBackup.retentionPending"
        static let enabled = "trio.cloudBackup.automaticEnabled"
        static let lastDailyCheckAt = "trio.cloudBackup.lastDailyCheckAt"
        static let lastSuccessfulUploadAt = "trio.cloudBackup.lastSuccessfulUploadAt"
        static let lastBackedAt = "trio.cloudBackup.lastBackedAt"
        static let lastFingerprint = "trio.cloudBackup.lastFingerprint"
    }

    private let cloud: TrioCloudBackupStoring
    private let defaults: UserDefaults
    private let queueURL: URL
    private let onboardingInProgress: () -> Bool
    private let captureOverride: ((TrioSettingsBackup.Origin, String?) async throws -> TrioSettingsBackup)?
    private var dailyTimer: Task<Void, Never>?
    private var onboardingObserver: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private var storage: FileStorage?
    private var settingsManager: SettingsManager?
    private var deviceManager: DeviceDataManager?
    #if canImport(UIKit)
        private var broadcaster: Broadcaster?
    #endif
    private var started = false
    private(set) var isUploading = false
    private(set) var lastError: Error?
    private(set) var lastRetentionError: Error?

    init(
        cloud: TrioCloudBackupStoring = TrioCloudBackupStore(),
        defaults: UserDefaults = .standard,
        queueURL: URL? = nil,
        onboardingInProgress: @escaping () -> Bool = { OnboardingManager.shared.shouldShowOnboarding },
        capture: ((TrioSettingsBackup.Origin, String?) async throws -> TrioSettingsBackup)? = nil
    ) {
        self.cloud = cloud
        self.defaults = defaults
        self.queueURL = queueURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".trio-cloud-backup-queue.json")
        self.onboardingInProgress = onboardingInProgress
        captureOverride = capture
    }

    /// Migrate legacy envelopes to settings-only queues, discarding credentials on disk.
    private struct LegacyQueueEnvelope: Decodable {
        let settings: TrioSettingsBackup
    }

    func loadQueue() throws -> [TrioSettingsBackup] {
        guard FileManager.default.fileExists(atPath: queueURL.path) else { return [] }
        // A corrupt queue is an error, never interpreted as an empty queue.
        let data = try Data(contentsOf: queueURL)
        if let snapshots = try? JSONDecoder().decode([TrioSettingsBackup].self, from: data) {
            return try snapshots.map { try $0.validated() }
        }
        let legacy = try JSONDecoder().decode([LegacyQueueEnvelope].self, from: data)
        let safe = try legacy.map { try $0.settings.validated() }
        try saveQueue(safe)
        return safe
    }

    private func saveQueue(_ queue: [TrioSettingsBackup]) throws {
        try JSONEncoder().encode(queue)
            .write(to: queueURL, options: [.atomic, .completeFileProtection])
    }

    private func snapshot(
        origin: TrioSettingsBackup.Origin,
        name: String? = nil
    ) async throws -> TrioSettingsBackup {
        if let captureOverride { return try await captureOverride(origin, name).validated() }
        guard let storage else { throw BackupError.incompleteConfiguration }
        return try await TrioSettingsBackup.capture(storage: storage, origin: origin, name: name)
    }


    deinit {
        dailyTimer?.cancel()
        if let onboardingObserver { Foundation.NotificationCenter.default.removeObserver(onboardingObserver) }
        if let accountObserver { Foundation.NotificationCenter.default.removeObserver(accountObserver) }
    }

    private func recordSuccess(_ snapshot: TrioSettingsBackup) {
        defer { Foundation.NotificationCenter.default.post(name: Self.uploadNotification, object: nil) }
        defaults.set(Date(), forKey: Keys.lastSuccessfulUploadAt)
        let previous = defaults.object(forKey: Keys.lastBackedAt) as? Date ?? .distantPast
        guard snapshot.createdAt >= previous else { return }
        defaults.set(snapshot.fingerprint, forKey: Keys.lastFingerprint)
        defaults.set(snapshot.createdAt, forKey: Keys.lastBackedAt)
    }

    var lastSuccessfulBackupDate: Date? {
        defaults.object(forKey: Keys.lastSuccessfulUploadAt) as? Date
            ?? defaults.object(forKey: Keys.lastBackedAt) as? Date
    }

    func restoreConfiguredApp(_ backup: TrioSettingsBackup) async throws {
        guard let settingsManager, let deviceManager else { throw BackupError.restoreFailed }
        guard deviceManager.pumpManager == nil else { throw BackupError.pumpNotReady }
        try await TrioCloudSettingsRestore.applyConfigured(backup, settingsManager: settingsManager, deviceManager: deviceManager)
        #if canImport(UIKit)
            if let basal = storage?.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) {
                broadcaster?.notify(BasalProfileObserver.self, on: .main) { $0.basalProfileDidChange(basal) }
            }
            let pumpSettings = settingsManager.pumpSettings
            broadcaster?.notify(PumpSettingsObserver.self, on: .main) { $0.pumpSettingsDidChange(pumpSettings) }
        #endif
        // Restores are a new configuration baseline. Recheck next launch.
        defaults.removeObject(forKey: Keys.lastDailyCheckAt)
        applicationDidBecomeActive()
    }

    func restoreDuringOnboarding(_ backup: TrioSettingsBackup) async throws {
        guard let settingsManager, let deviceManager else { throw BackupError.restoreFailed }
        guard deviceManager.pumpManager == nil else { throw BackupError.pumpNotReady }
        try await TrioCloudSettingsRestore.applyDuringOnboarding(
            backup, settingsManager: settingsManager, deviceManager: deviceManager
        )
    }

    var automaticEnabled: Bool {
        get { (defaults.object(forKey: Keys.enabled) as? Bool) ?? true }
        set {
            defaults.set(newValue, forKey: Keys.enabled)
            if newValue { applicationDidBecomeActive() }
            else { dailyTimer?.cancel(); dailyTimer = nil }
        }
    }

    func start(resolver: Resolver) {
        guard !started else { return }
        started = true
        storage = resolver.resolve(FileStorage.self)
        settingsManager = resolver.resolve(SettingsManager.self)
        deviceManager = resolver.resolve(DeviceDataManager.self)
        #if canImport(UIKit)
            broadcaster = resolver.resolve(Broadcaster.self)
        #endif
        onboardingObserver = Foundation.NotificationCenter.default.addObserver(
            forName: .onboardingCompleted, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.defaults.removeObject(forKey: Keys.lastDailyCheckAt)
                self?.applicationDidBecomeActive()
            }
        }
        accountObserver = Foundation.NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Discard the previous account's queue; capture local settings for the new account.
                do { try self.saveQueue([]) } catch { self.lastError = error; return }
                self.defaults.removeObject(forKey: Keys.lastFingerprint)
                self.defaults.removeObject(forKey: Keys.lastBackedAt)
                self.defaults.removeObject(forKey: Keys.lastDailyCheckAt)
                self.applicationDidBecomeActive()
            }
        }
        applicationDidBecomeActive()
    }

    static func isDailyCheckDue(last: Date?, now: Date = Date()) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= checkInterval
    }

    func applicationDidBecomeActive() {
        dailyTimer?.cancel()
        dailyTimer = nil
        guard !onboardingInProgress(), !TrioCloudSettingsRestore.isRestoring else { return }
        Task { [weak self] in await self?.runAutomaticBackup() }
        scheduleDailyCheck()
    }

    private func scheduleDailyCheck() {
        guard automaticEnabled, !onboardingInProgress() else { return }
        let last = defaults.object(forKey: Keys.lastDailyCheckAt) as? Date
        let seconds = max(5, (last?.addingTimeInterval(Self.checkInterval) ?? Date()).timeIntervalSinceNow)
        dailyTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dailyTimer = nil
            await self?.runAutomaticBackup()
            self?.scheduleDailyCheck()
        }
    }

    /// A successful comparison advances the daily clock even when settings are unchanged.
    /// Queue changed settings durably before attempting upload.
    func runAutomaticBackup(capturePending: Bool = true, now: Date = Date()) async {
        guard !isUploading, !TrioCloudSettingsRestore.isRestoring, !onboardingInProgress() else { return }
        isUploading = true
        defer { isUploading = false; scheduleDailyCheck() }
        do {
            var queue = try loadQueue()
            if capturePending, automaticEnabled,
               Self.isDailyCheckDue(last: defaults.object(forKey: Keys.lastDailyCheckAt) as? Date, now: now)
            {
                let candidate = try await snapshot(origin: .automatic)
                let preceding = queue.last?.fingerprint ?? defaults.string(forKey: Keys.lastFingerprint)
                let unchanged = try preceding == candidate.fingerprint || TrioSettingsBackup.matchesLegacyFingerprint(
                    preceding, configuration: candidate.configuration
                )
                if unchanged, queue.isEmpty { defaults.set(candidate.fingerprint, forKey: Keys.lastFingerprint) }
                if !unchanged {
                    // After reinstall, use the newest valid cloud backup as the baseline.
                    var alreadyStored = false
                    if preceding == nil {
                        // An offline baseline query must not prevent durable local capture.
                        do {
                            if let entry = try await cloud.list().first(where: { $0.validationMessage == nil }) {
                                let existing = try await cloud.download(id: entry.id)
                                alreadyStored = existing.fingerprint == candidate.fingerprint
                            }
                        } catch {
                            // Reuse the queued UUID when the previous upload outcome is unknown.
                        }
                    }
                    if !alreadyStored {
                        queue.append(candidate)
                        try saveQueue(queue)
                    } else {
                        defaults.set(candidate.fingerprint, forKey: Keys.lastFingerprint)
                    }
                }
                defaults.set(now, forKey: Keys.lastDailyCheckAt)
            }
            while let pending = queue.first(where: { automaticEnabled || $0.origin == .manual }) {
                _ = try await cloud.upload(pending)
                queue.removeAll { $0.id == pending.id }
                try saveQueue(queue)
                recordSuccess(pending)
                defaults.set(true, forKey: Keys.retentionPending)
            }
            await maintainRetentionIfNeeded()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    private func withBackupOperation<Value>(_ operation: () async throws -> Value) async throws -> Value {
        guard !isUploading, !TrioCloudSettingsRestore.isRestoring else { throw BackupError.operationInProgress }
        isUploading = true
        defer { isUploading = false; scheduleDailyCheck() }
        return try await operation()
    }

    func createManualBackup(name: String?) async throws -> TrioCloudBackupEntry {
        guard let name = TrioSettingsBackup.normalizedName(name) else { throw BackupError.backupNameRequired }
        return try await withBackupOperation {
            let snapshot = try await snapshot(origin: .manual, name: name)
            // Manual snapshots stay independent even if the fingerprint is identical.
            var queue = try loadQueue()
            queue.append(snapshot)
            try saveQueue(queue)
            let entry = try await cloud.upload(snapshot)
            queue.removeAll { $0.id == snapshot.id }
            try saveQueue(queue)
            recordSuccess(snapshot)
            defaults.set(Date(), forKey: Keys.lastDailyCheckAt)
            defaults.set(true, forKey: Keys.retentionPending)
            await maintainRetentionIfNeeded(protecting: [entry.id])
            return entry
        }
    }

    func exportBackupFile() async throws -> URL {
        try await withBackupOperation {
            let snapshot = try await snapshot(origin: .manual)
            return try Self.exportBackupFile(snapshot)
        }
    }

    static func exportBackupFile(_ candidate: TrioSettingsBackup) throws -> URL {
        let snapshot = try candidate.validated()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= TrioSettingsBackup.maximumSize else { throw BackupError.backupTooLarge }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrioSettings_\(formatter.string(from: snapshot.createdAt)).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func pendingOperationCount() throws -> Int { try loadQueue().count }

    func listBackups() async throws -> [TrioCloudBackupEntry] {
        try await cloud.list()
    }

    func downloadBackup(id: String) async throws -> TrioSettingsBackup {
        try await cloud.download(id: id)
    }

    func deleteBackup(id: String) async throws {
        try await withBackupOperation {
            let queue = try loadQueue()
            try await cloud.delete(id: id)
            // An ambiguous prior upload must not recreate a backup the user deleted.
            try saveQueue(queue.filter { $0.id.uuidString != id })
            Foundation.NotificationCenter.default.post(name: Self.changesNotification, object: nil)
        }
    }

    func renameBackup(id: String, name: String) async throws -> TrioCloudBackupEntry {
        guard let name = TrioSettingsBackup.normalizedName(name) else { throw BackupError.backupNameRequired }
        return try await withBackupOperation {
            var queue = try loadQueue()
            let entry = try await cloud.rename(id: id, name: name)
            if let index = queue.firstIndex(where: { $0.id.uuidString == id }) {
                queue[index].name = name
                try saveQueue(queue)
            }
            Foundation.NotificationCenter.default.post(name: Self.changesNotification, object: nil)
            return entry
        }
    }

    func retentionLimit(for origin: TrioSettingsBackup.Origin) -> Int {
        let key = origin == .manual ? Keys.manualRetention : Keys.automaticRetention
        let value = defaults.integer(forKey: key)
        return Self.retentionChoices.contains(value) ? value : 15
    }

    func setRetentionLimit(_ limit: Int, for origin: TrioSettingsBackup.Origin) async throws {
        guard Self.retentionChoices.contains(limit) else { throw BackupError.invalidRetentionLimit }
        return try await withBackupOperation {
            defaults.set(limit, forKey: origin == .manual ? Keys.manualRetention : Keys.automaticRetention)
            defaults.set(true, forKey: Keys.retentionPending)
            await maintainRetentionIfNeeded()
            if let lastRetentionError { throw lastRetentionError }
        }
    }

    /// Prune after confirmed upload; persist failed cleanup for a foreground retry.
    private func maintainRetentionIfNeeded(protecting protected: Set<String> = []) async {
        guard defaults.bool(forKey: Keys.retentionPending) else { return }
        do {
            let entries = try await cloud.list()
            let queued = Set(try loadQueue().map(\.id.uuidString))
            var deferred = false
            for origin in TrioSettingsBackup.Origin.allCases {
                let group = entries.filter { $0.origin == origin && $0.validationMessage == nil }
                    .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
                let protectedCount = group.filter { protected.contains($0.id) }.count
                let remaining = group.filter { !protected.contains($0.id) }
                let excess = remaining.dropFirst(max(0, retentionLimit(for: origin) - protectedCount))
                for entry in excess.reversed() {
                    if queued.contains(entry.id) { deferred = true
                        continue }
                    try await cloud.delete(id: entry.id)
                }
            }
            defaults.set(deferred, forKey: Keys.retentionPending)
            lastRetentionError = nil
            Foundation.NotificationCenter.default.post(name: Self.changesNotification, object: nil)
        } catch { lastRetentionError = error }
    }
}
