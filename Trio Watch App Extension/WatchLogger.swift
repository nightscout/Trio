//
//  WatchLogger.swift
//  Trio
//
//  Created by Cengiz Deniz on 18.04.25.
//
import Foundation
import WatchConnectivity

final class WatchLogger {
    static let shared = WatchLogger()

    private var logs: [String] = []
    private let maxEntries = 300
    private let flushInterval: TimeInterval = 7.5 * 60
    private let flushSizeThreshold = 75

    private var lastFlush = Date()
    private let session = WCSession.default

    private init() {
        Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            self.flushIfNeeded(force: false)
        }
    }

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }

    func log(_ message: String, force: Bool = false, function: String = #function, file: String = #fileID, line: Int = #line) {
        let shortFile = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] [\(shortFile):\(line)] \(function) → \(message)"
        logs.append(entry)

        if logs.count > maxEntries {
            logs.removeFirst()
        }

        print(entry)
        flushIfNeeded(force: force)
    }

    func flushIfNeeded(force: Bool = false) {
        let now = Date()
        let shouldFlush = force || now.timeIntervalSince(lastFlush) >= flushInterval || logs.count >= flushSizeThreshold

        if shouldFlush {
            flushToPhone()
        }
    }

    private func flushToPhone() {
        guard !logs.isEmpty else { return }

        let payload: [String: Any] = [
            "watchLogs": logs.joined(separator: "\n")
        ]

        if session.activationState != .activated {
            session.activate()
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("⌚️ Failed to flush logs to phone via sendMessage: \(error.localizedDescription)")
                self.persistLogsLocally()
            }
        }

        lastFlush = Date()
        logs.removeAll()
    }

    func persistLogsLocally() {
        let logDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("logs", isDirectory: true)

        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let logFile = logDir.appendingPathComponent("watch_log.txt")
        let previousLogFile = logDir.appendingPathComponent("watch_log_prev.txt")
        let startOfDay = Calendar.current.startOfDay(for: Date())

        // Rotate if necessary
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let creationDate = attributes[.creationDate] as? Date,
           creationDate < startOfDay
        {
            try? FileManager.default.removeItem(at: previousLogFile)
            try? FileManager.default.moveItem(at: logFile, to: previousLogFile)
            FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: [.creationDate: startOfDay])
        }

        let fullLog = logs.joined(separator: "\n") + "\n"
        if let data = fullLog.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                _ = try? handle.seekToEnd()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    /// Optional recovery mechanism:
    /// Use this on startup to attempt flushing local file logs to phone
    func flushPersistedLogs() {
        let logDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("logs", isDirectory: true)
        let logFile = logDir.appendingPathComponent("watch_log.txt")

        guard let data = try? Data(contentsOf: logFile),
              let logString = String(data: data, encoding: .utf8),
              !logString.isEmpty
        else { return }

        let payload: [String: Any] = [
            "watchLogs": logString
        ]

        if session.activationState != .activated {
            session.activate()
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("⌚️ Failed to resend persisted logs: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: logFile)
        } else {
            _ = session.transferUserInfo(payload)
            try? FileManager.default.removeItem(at: logFile)
        }
    }
}
