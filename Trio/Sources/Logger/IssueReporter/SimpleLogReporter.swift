import Foundation
import System

enum SimpleLogReporter {
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
        let descriptor = try FileDescriptor.open(
            FilePath(fileURL.path),
            .writeOnly,
            options: [.append, .create],
            permissions: [.ownerReadWrite, .groupRead, .otherRead]
        )
        try descriptor.closeAfter { _ = try descriptor.writeAll(self) }
    }
}
