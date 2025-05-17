import Foundation
import SwiftDate

final class SimpleLogReporter: IssueReporter {
    private let fileManager = FileManager.default

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }

    func setup() {}

    func setUserIdentifier(_: String?) {}

    func reportNonFatalIssue(withName _: String, attributes _: [String: String]) {}

    func reportNonFatalIssue(withError _: NSError) {}

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        if !fileManager.fileExists(atPath: SimpleLogReporter.logDir) {
            try? fileManager.createDirectory(
                atPath: SimpleLogReporter.logDir,
                withIntermediateDirectories: false,
                attributes: nil
            )
        }

        if !fileManager.fileExists(atPath: SimpleLogReporter.logFile) {
            createFile(at: startOfDay)
        } else {
            if let attributes = try? fileManager.attributesOfItem(atPath: SimpleLogReporter.logFile),
               let creationDate = attributes[.creationDate] as? Date, creationDate < startOfDay
            {
                try? fileManager.removeItem(atPath: SimpleLogReporter.logFilePrev)
                try? fileManager.moveItem(atPath: SimpleLogReporter.logFile, toPath: SimpleLogReporter.logFilePrev)
                createFile(at: startOfDay)
            }
        }

        let logEntry = "\(dateFormatter.string(from: now)) [\(category)] \(file.file) - \(function) - \(line) - \(message)\n"
        let data = logEntry.data(using: .utf8)!
        try? data.append(fileURL: URL(fileURLWithPath: SimpleLogReporter.logFile))
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

    static func appendToWatchLog(_ logContent: String) {
        let fileManager = FileManager.default
        let logDir = getDocumentsDirectory().appendingPathComponent("logs")
        let logFile = URL(fileURLWithPath: watchLogFile)
        let prevLogFile = URL(fileURLWithPath: watchLogFilePrev)

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

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

private extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}
