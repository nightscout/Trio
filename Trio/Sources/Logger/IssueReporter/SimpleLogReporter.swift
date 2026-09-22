import Foundation
import SwiftDate
import System

/// Appends log lines to `Documents/logs/log.txt`, rotating daily.
/// Lines are buffered and written in batches on a serial queue.
final class SimpleLogReporter: IssueReporter {
    /// Longest a line waits in memory before it reaches the disk.
    private static let flushInterval: TimeInterval = 1
    /// Pending lines that trigger an immediate flush, so bursts don't wait out the interval.
    private static let flushThreshold = 64
    /// Caps the buffer, including lines put back after a failed write.
    private static let maxBufferedLines = 10000

    private let fileManager = FileManager.default

    /// POSIX locale keeps the fixed format on the Gregorian calendar.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Serializes every write to the log file, including the ones from `flush()`.
    private let writeQueue = DispatchQueue(label: "SimpleLogReporter.writeQueue", qos: .utility)
    private let bufferLock = NSLock(label: "SimpleLogReporter.bufferLock")
    private var buffer: [String] = []
    private var flushScheduled = false
    private var droppedLines = 0

    func setup() {}

    func setUserIdentifier(_: String?) {}

    func reportNonFatalIssue(withName _: String, attributes _: [String: String]) {}

    func reportNonFatalIssue(withError _: NSError) {}

    func log(_ category: String, _ message: String, date: Date, file: String, function: String, line: UInt) {
        let timestamp = SimpleLogReporter.dateFormatter.string(from: date)
        enqueue("\(timestamp) [\(category)] \(file.file) - \(function) - \(line) - \(message)\n")
    }

    /// Writes everything buffered so far and returns once it is on disk.
    ///
    /// Must not be called from `writeQueue`.
    func flush() {
        writeQueue.sync { self.drainAndWrite() }
    }

    private func enqueue(_ entry: String) {
        let flushNow: Bool = bufferLock.perform {
            if buffer.count >= SimpleLogReporter.maxBufferedLines {
                buffer.removeFirst()
                droppedLines += 1
            }
            buffer.append(entry)

            if buffer.count >= SimpleLogReporter.flushThreshold {
                return true
            }
            scheduleFlush()
            return false
        }

        if flushNow {
            writeQueue.async { [weak self] in self?.drainAndWrite() }
        }
    }

    /// Queues a drain `flushInterval` from now unless one is already pending.
    /// Must be called with `bufferLock` held.
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        writeQueue.asyncAfter(deadline: .now() + SimpleLogReporter.flushInterval) { [weak self] in
            self?.drainAndWrite()
        }
    }

    /// Takes everything out of the buffer and appends it in a single write.
    /// Always runs on `writeQueue`.
    private func drainAndWrite() {
        let lines: [String] = bufferLock.perform {
            flushScheduled = false
            guard !buffer.isEmpty else { return [] }

            var lines = buffer
            buffer.removeAll(keepingCapacity: true)
            if droppedLines > 0 {
                lines.insert("--- \(droppedLines) log line(s) dropped: log buffer overflowed ---\n", at: 0)
                droppedLines = 0
            }
            return lines
        }

        guard !lines.isEmpty, let data = lines.joined().data(using: .utf8) else { return }

        prepareLogFile()
        do {
            try data.append(fileURL: URL(fileURLWithPath: SimpleLogReporter.logFile))
        } catch {
            // Put the lines back and retry rather than silently losing the batch.
            bufferLock.perform {
                buffer.insert(contentsOf: lines, at: 0)
                let overflow = buffer.count - SimpleLogReporter.maxBufferedLines
                if overflow > 0 {
                    buffer.removeFirst(overflow)
                    droppedLines += overflow
                }
                scheduleFlush()
            }
        }
    }

    /// Creates the log file if missing and rotates it once a day.
    private func prepareLogFile() {
        let startOfDay = Calendar.current.startOfDay(for: Date())

        if !fileManager.fileExists(atPath: SimpleLogReporter.logDir) {
            try? fileManager.createDirectory(
                atPath: SimpleLogReporter.logDir,
                withIntermediateDirectories: false,
                attributes: nil
            )
        }

        if !fileManager.fileExists(atPath: SimpleLogReporter.logFile) {
            createFile(at: startOfDay)
        } else if let attributes = try? fileManager.attributesOfItem(atPath: SimpleLogReporter.logFile),
                  let creationDate = attributes[.creationDate] as? Date, creationDate < startOfDay
        {
            try? fileManager.removeItem(atPath: SimpleLogReporter.logFilePrev)
            try? fileManager.moveItem(atPath: SimpleLogReporter.logFile, toPath: SimpleLogReporter.logFilePrev)
            createFile(at: startOfDay)
        }
    }

    private func createFile(at date: Date) {
        fileManager.createFile(atPath: SimpleLogReporter.logFile, contents: nil, attributes: [.creationDate: date])
    }

    static var logFile: String {
        getDocumentsDirectory().appendingPathComponent("logs/log.txt").path
    }

    static var logDir: String {
        getDocumentsDirectory().appendingPathComponent("logs").path
    }

    static var logFilePrev: String {
        getDocumentsDirectory().appendingPathComponent("logs/log_prev.txt").path
    }

    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
}

extension SimpleLogReporter {
    static var watchLogFile: String {
        getDocumentsDirectory().appendingPathComponent("logs/watch_log.txt").path
    }

    static var watchLogFilePrev: String {
        getDocumentsDirectory().appendingPathComponent("logs/watch_log_prev.txt").path
    }

    /// Serializes watch log writes off the `WCSession` delegate queue.
    private static let watchLogQueue = DispatchQueue(label: "SimpleLogReporter.watchLogQueue", qos: .utility)

    /// Waits for the queued watch log writes to reach the disk.
    ///
    /// Must not be called from `watchLogQueue`.
    static func flushWatchLog() {
        watchLogQueue.sync {}
    }

    static func appendToWatchLog(_ logContent: String) {
        watchLogQueue.async {
            let fileManager = FileManager.default
            let logDir = getDocumentsDirectory().appendingPathComponent("logs")
            let logFile = URL(fileURLWithPath: watchLogFile)
            let prevLogFile = URL(fileURLWithPath: watchLogFilePrev)

            let startOfDay = Calendar.current.startOfDay(for: Date())

            // Create logs directory if needed
            if !fileManager.fileExists(atPath: logDir.path) {
                try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
            }

            // Rotate if needed
            if fileManager.fileExists(atPath: logFile.path),
               let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < startOfDay
            {
                try? fileManager.removeItem(at: prevLogFile)
                try? fileManager.moveItem(at: logFile, to: prevLogFile)
                fileManager.createFile(atPath: logFile.path, contents: nil, attributes: [.creationDate: startOfDay])
            }

            if let data = (logContent + "\n").data(using: .utf8) {
                try? data.append(fileURL: logFile)
            }
        }
    }
}

private extension Data {
    func append(fileURL: URL) throws {
        let descriptor = try FileDescriptor.open(
            FilePath(fileURL.path),
            .writeOnly,
            options: [.append, .create],
            permissions: [.ownerReadWrite, .groupRead, .otherRead]
        )
        try descriptor.closeAfter { _ = try descriptor.writeAll(self) }
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}
