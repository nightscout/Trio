import CoreData
import Foundation
import LoopKit
import OSLog
import Swinject
import TidepoolServiceKit
import UIKit

final class LogExport: Injectable {
    enum Kind {
        case all
        case pump
        case cgm
    }

    @Injected() private var deviceLogStore: DeviceLogStore!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var fetchGlucoseManager: FetchGlucoseManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var keychain: Keychain!
    @Injected() private var tidepoolManager: TidepoolManager!

    // Read-only view of BaseAlertHistoryStorage's persisted history
    static let alertHistoryKey = "openaps.monitor.alertHistory.data"

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private let appLog: () -> any LogSink
    private let managers: (@MainActor() -> (pump: DeviceManager?, cgm: DeviceManager?))?
    private let traceSubsystems: [String: [String]]
    private let coreDataStack: CoreDataStack?
    private let storedValues: SensitiveValues
    private let requestWatchLogs: (() async -> Void)?

    init(resolver: Resolver) {
        appLog = { TrioLogger.sink }
        managers = nil
        traceSubsystems = OSLogCapture.subsystems
        coreDataStack = CoreDataStack.shared
        storedValues = SensitiveValues()
        requestWatchLogs = { await WatchLogIngest.shared.requestLatest() }
        injectServices(resolver)
    }

    init(
        appLog: any LogSink,
        deviceLogStore: DeviceLogStore,
        pump: DeviceManager?,
        cgm: DeviceManager?,
        storedValues: SensitiveValues = SensitiveValues(),
        coreDataStack: CoreDataStack? = nil,
        requestWatchLogs: (() async -> Void)? = nil
    ) {
        self.appLog = { appLog }
        managers = { (pump, cgm) }
        traceSubsystems = [:]
        self.coreDataStack = coreDataStack
        self.storedValues = storedValues
        self.requestWatchLogs = requestWatchLogs
        self.deviceLogStore = deviceLogStore
    }

    func makeFile(_ kind: Kind, days: Int) async throws -> URL {
        let backgroundTask = await BackgroundTask(name: "Share Logs")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let started = Date()
        do {
            let file = try await writeLog(kind, days: days, into: directory.appendingPathComponent("log", isDirectory: true))
            try Task.checkCancellation()
            let written = Date()
            let archive = try Self.zip(file, in: directory)
            let size = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            info(
                .storage,
                "Log file prepared in \(String(format: "%.1f", Date().timeIntervalSince(started))) s, zipped in \(String(format: "%.1f", Date().timeIntervalSince(written))) s, \(size / 1024) KB"
            )
            await backgroundTask.end()
            return archive
        } catch {
            try? FileManager.default.removeItem(at: directory)
            await backgroundTask.end()
            throw error
        }
    }

    static func discard(_ file: URL) {
        // Each file gets its own temporary directory
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    // NSFileCoordinator zips a directory for upload; the folder name becomes the zip's top level
    private static func zip(_ file: URL, in directory: URL) throws -> URL {
        let name = file.deletingPathExtension().lastPathComponent
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.moveItem(at: file.deletingLastPathComponent(), to: folder)
        let archive = directory.appendingPathComponent("\(name).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: archive)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        try? FileManager.default.removeItem(at: folder)
        return archive
    }

    func writeLog(_ kind: Kind, days: Int, into directory: URL) async throws -> URL {
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-Double(max(days, 1)) * 24 * 60 * 60), end: now)
        let (pump, cgm) = await deviceSnapshots()

        var header = LogFileHeader(kind: kind, days: days, created: now, pump: pump, cgm: cgm)
        if kind == .all {
            if let settingsManager {
                header.settings = LogFileHeader.settingsLines(
                    settingsManager.settings,
                    settingsManager.preferences,
                    settingsManager.pumpSettings
                )
            }
            header.alerts = Self.alerts(in: window)
        }

        // Later assignments win when one manager is both pump and CGM
        var deviceLabels: [String: String] = [:]
        if kind != .pump, let cgm { deviceLabels[cgm.identifier] = "CGM" }
        if kind != .cgm, let pump { deviceLabels[pump.identifier] = "Pump" }
        var traceLabels: [String: String] = [:]
        for (identifier, label) in deviceLabels {
            for subsystem in traceSubsystems[identifier] ?? [] {
                traceLabels[subsystem] = label
            }
        }
        let filter: String? = kind == .all ? nil : deviceLabels.keys.first
        let appLog = kind == .all ? self.appLog() : nil
        if appLog != nil {
            await requestWatchLogs?()
        }
        await appLog?.flush()
        let traceStore = traceLabels.isEmpty ? nil : try? OSLogStore(scope: .currentProcessIdentifier)
        let redactor = Redactor(exactValues: try await sensitiveValues(in: window))
        let algorithmStack = kind == .all ? coreDataStack : nil

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(header.title) \(Self.fileStamp(now)).txt")
        try await LogFileWriter.write(header: header.text, window: window, to: url, redactor: redactor) { slice in
            var lines: [LogLine] = []
            if let appLog {
                lines += await appLog.records(in: slice, minimumLevel: .debug).map(Self.line)
            }
            if let deviceLogStore, kind == .all || filter != nil {
                lines += await deviceLogStore.entries(in: slice, managerIdentifier: filter).map {
                    Self.line(for: $0, source: deviceLabels[$0.managerIdentifier] ?? $0.managerIdentifier)
                }
            }
            if let traceStore {
                lines += OSLogCapture.lines(from: traceStore, sources: traceLabels, in: slice)
            }
            if let algorithmStack {
                lines += await Self.algorithmLines(in: slice, from: algorithmStack)
            }
            return lines
        }
        return url
    }

    @MainActor private func currentManagers() -> (pump: DeviceManager?, cgm: DeviceManager?) {
        if let managers { return managers() }
        return (
            deviceDataManager?.pumpManager,
            fetchGlucoseManager?.cgmGlucoseSourceType == .plugin ? fetchGlucoseManager?.cgmManager : nil
        )
    }

    @MainActor private func deviceSnapshots() -> (LogFileHeader.Device?, LogFileHeader.Device?) {
        let (pump, cgm) = currentManagers()
        return (pump.map(Self.snapshot), cgm.map(Self.snapshot))
    }

    private static func snapshot(_ manager: DeviceManager) -> LogFileHeader.Device {
        LogFileHeader.Device(
            title: manager.localizedTitle,
            identifier: manager.pluginIdentifier,
            description: String(reflecting: manager)
        )
    }

    static func line(for record: LogRecord) -> LogLine {
        let level: String
        switch record.level {
        case .warning: level = "WARNING: "
        case .error: level = "ERROR: "
        case .fault: level = "FAULT: "
        case .debug,
             .info,
             .notice: level = ""
        }
        if record.category.hasPrefix(WatchLogIngest.categoryPrefix) {
            let category = record.category.dropFirst(WatchLogIngest.categoryPrefix.count)
            return LogLine(date: record.timestamp, source: "Watch", text: "\(level)[\(category)] \(record.message)")
        }
        return LogLine(date: record.timestamp, source: "Trio", text: "\(level)[\(record.category)] \(record.message)")
    }

    static func line(for entry: StoredDeviceLogEntry, source: String) -> LogLine {
        LogLine(date: entry.timestamp, source: source, text: "[\(entry.type.rawValue)] \(entry.message)")
    }

    static func algorithmLines(in window: DateInterval, from stack: CoreDataStack) async -> [LogLine] {
        let context = stack.newTaskContext()
        context.name = "logExportDeterminations"
        do {
            return try await context.perform {
                let request: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
                request.predicate = NSPredicate(
                    format: "deliverAt >= %@ AND deliverAt <= %@",
                    window.start as NSDate,
                    window.end as NSDate
                )
                request.fetchBatchSize = 100
                return try context.fetch(request).compactMap { determination in
                    determination.deliverAt.map { LogLine(date: $0, source: "Algorithm", text: algorithmText(determination)) }
                }
            }
        } catch {
            warning(.storage, "Reading determinations for the log file failed", error: error)
            return []
        }
    }

    private static func algorithmText(_ determination: OrefDetermination) -> String {
        func number(_ value: NSDecimalNumber?) -> String? {
            value.flatMap { numberFormatter.string(from: $0) }
        }
        var parts = [determination.enacted ? "enacted" : "suggested"]
        if let glucose = number(determination.glucose) { parts.append("BG \(glucose)") }
        if let iob = number(determination.iob) { parts.append("IOB \(iob)") }
        parts.append("COB \(determination.cob)")
        if let rate = number(determination.rate) {
            parts.append(number(determination.duration).map { "rate \(rate)/\($0)m" } ?? "rate \(rate)")
        }
        if let smb = number(determination.smbToDeliver) { parts.append("SMB \(smb)") }
        if let eventual = number(determination.eventualBG) { parts.append("eventual \(eventual)") }
        if let reason = determination.reason, !reason.isEmpty { parts.append(reason) }
        return parts.joined(separator: " · ")
    }

    private static func alerts(in window: DateInterval) -> [AlertEntry] {
        guard let data = UserDefaults.standard.data(forKey: alertHistoryKey),
              let alerts = try? JSONCoding.decoder.decode([AlertEntry].self, from: data)
        else { return [] }
        return alerts.filter { window.contains($0.issuedDate) }
    }

    private func sensitiveValues(in window: DateInterval) async throws -> [Redactor.ExactValue] {
        var values = await currentSensitiveValues()
        // Devices replaced during the window are only known from the device log
        if let deviceLogStore {
            for slice in LogFileWriter.slices(of: window) {
                try Task.checkCancellation()
                for entry in await deviceLogStore.entries(in: slice) {
                    values.add(entry.deviceIdentifier, .device)
                }
            }
        }
        return values.values
    }

    @MainActor private func currentSensitiveValues() -> SensitiveValues {
        var values = storedValues
        if let keychain {
            values.addNightscout(
                url: keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                secret: keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
            )
            values.addTrioIdentifiers()
        }
        values.add(tidepool: tidepoolManager?.getTidepoolServiceUI() as? TidepoolService)
        let (pump, cgm) = currentManagers()
        for manager in [pump, cgm].compactMap({ $0 }) {
            values.add(manager)
        }
        return values
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: date)
    }
}

private extension LogExport {
    @MainActor final class BackgroundTask {
        private var identifier: UIBackgroundTaskIdentifier = .invalid

        init(name: String) {
            identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                MainActor.assumeIsolated { self?.end() }
            }
        }

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}
