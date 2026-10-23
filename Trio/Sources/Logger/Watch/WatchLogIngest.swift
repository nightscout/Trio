import Foundation
import os
import WatchConnectivity

final class WatchLogIngest: @unchecked Sendable {
    static let shared = WatchLogIngest()

    struct Batch: Sendable {
        let file: URL
        let installID: String
        let firstSeq: UInt64
        let lastSeq: UInt64
    }

    static let categoryPrefix = "Watch/"
    static let requestTimeout: Duration = .seconds(2)
    private static let lastSeqKey = "WatchLogIngest.lastSeq"

    private let defaults: UserDefaults
    private let sink: () -> any LogSink
    private let queue = DispatchQueue(label: "WatchLogIngest.queue", qos: .utility)
    private let ingestedBatches = OSAllocatedUnfairLock(initialState: 0)

    init(defaults: UserDefaults = .standard, sink: @escaping () -> any LogSink = { TrioLogger.sink }) {
        self.defaults = defaults
        self.sink = sink
    }

    static var stagingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WatchLogs", isDirectory: true)
    }

    // Runs inside session(_:didReceive:); the system deletes the received file once that returns
    static func stage(_ file: URL, metadata: [String: Any]?, into directory: URL = stagingDirectory) -> Batch? {
        guard let metadata,
              (metadata[WatchLogTransfer.marker] as? NSNumber)?.intValue == WatchLogTransfer.version,
              let installID = metadata[WatchLogTransfer.installID] as? String, !installID.isEmpty,
              let firstSeq = (metadata[WatchLogTransfer.firstSeq] as? NSNumber)?.uint64Value,
              let lastSeq = (metadata[WatchLogTransfer.lastSeq] as? NSNumber)?.uint64Value,
              firstSeq <= lastSeq,
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= WatchLogTransfer.maxFileSize
        else { return nil }

        let staged = directory.appendingPathComponent("\(UUID().uuidString).jsonl")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: staged)
        } catch {
            warning(.watch, "Copying a received watch log file failed", error: error)
            return nil
        }
        return Batch(file: staged, installID: installID, firstSeq: firstSeq, lastSeq: lastSeq)
    }

    // Returns the seq to acknowledge to the watch, once the records are stored
    @discardableResult func ingest(_ batch: Batch) async -> UInt64 {
        defer { try? FileManager.default.removeItem(at: batch.file) }
        let previous = queue.sync { lastSeq(for: batch.installID) }
        let data = (try? Data(contentsOf: batch.file)) ?? Data()
        let fresh = WatchLogEntry.entries(fromJSONLines: data)
            .filter { $0.seq > previous }
            .sorted { $0.seq < $1.seq }
        let sink = self.sink()
        fresh.map(Self.record).forEach(sink.accept)
        await sink.flush()

        // Only what was parsed and stored; a cut-off file gets the rest resent
        let ack = queue.sync {
            let ack = max(lastSeq(for: batch.installID), fresh.last?.seq ?? 0)
            var lastSeqs = defaults.dictionary(forKey: Self.lastSeqKey) as? [String: NSNumber] ?? [:]
            lastSeqs[batch.installID] = NSNumber(value: ack)
            defaults.set(lastSeqs, forKey: Self.lastSeqKey)
            return ack
        }
        ingestedBatches.withLock { $0 += 1 }
        return ack
    }

    private func lastSeq(for installID: String) -> UInt64 {
        let lastSeqs = defaults.dictionary(forKey: Self.lastSeqKey) as? [String: NSNumber] ?? [:]
        return lastSeqs[installID]?.uint64Value ?? 0
    }

    func receive(_ file: URL, metadata: [String: Any]?) {
        guard metadata?[WatchLogTransfer.marker] != nil else { return }
        guard let batch = Self.stage(file, metadata: metadata) else {
            warning(.watch, "Rejected a watch log file with invalid metadata or over the size limit")
            return
        }
        Task.detached(priority: .utility) {
            let ack = await self.ingest(batch)
            Self.send([WatchLogTransfer.ack: NSNumber(value: ack), WatchLogTransfer.installID: batch.installID])
        }
    }

    // Asks the watch for its newest entries and waits briefly for them to land
    func requestLatest(timeout: Duration = requestTimeout) async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let before = ingestedBatches.withLock { $0 }
        Self.send([WatchLogTransfer.request: true])
        guard session.isReachable else { return }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            if ingestedBatches.withLock({ $0 }) != before { return }
        }
    }

    private static func send(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    static func record(_ entry: WatchLogEntry) -> LogRecord {
        LogRecord(
            timestamp: entry.date,
            level: entry.level.logLevel,
            category: categoryPrefix + entry.category.name,
            message: entry.message,
            file: "Watch",
            function: "",
            line: 0,
            launchID: LaunchID.current
        )
    }

    private static let legacyTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    // String payloads from watch builds before structured logging
    static func legacyRecords(from payload: String, receivedAt date: Date = Date()) -> [LogRecord] {
        payload.split(whereSeparator: \.isNewline).compactMap { line in
            var message = line.trimmingCharacters(in: .whitespaces)
            guard !message.isEmpty else { return nil }
            var timestamp = date
            if message.hasPrefix("["), let close = message.firstIndex(of: "]"),
               let parsed = legacyTimestampFormatter
               .date(from: String(message[message.index(after: message.startIndex) ..< close]))
            {
                timestamp = parsed
                message = message[message.index(after: close)...].trimmingCharacters(in: .whitespaces)
            }
            return LogRecord(
                timestamp: timestamp,
                level: .debug,
                category: categoryPrefix + "Legacy",
                message: message,
                file: "Watch",
                function: "",
                line: 0,
                launchID: LaunchID.current
            )
        }
    }
}

private extension WatchLogEntry.Level {
    var logLevel: LogLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fault: return .fault
        }
    }
}
