import Combine
import OSLog

class DanaLogger {
    private let logger: Logger
    private let fileManager = FileManager.default

    init(category: String) {
        logger = Logger(subsystem: "com.randallknutson.DanaKit", category: category)
    }

    public func debug(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        #if DANAKIT_DEBUG_LOGGING
            let message = "\(file.file) - \(function)#\(line): \(msg)"
            logger.debug("\(message, privacy: .public)")
        #endif
    }

    public func info(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.info("\(message, privacy: .public)")
        writeToFile(message, .info)
    }

    public func warning(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.warning("\(message, privacy: .public)")
        writeToFile(message, .notice)
    }

    public func error(_ msg: String, file: String = #file, _ function: String = #function, _ line: Int = #line) {
        let message = "\(file.file) - \(function)#\(line): \(msg)"
        logger.error("\(message, privacy: .public)")
        writeToFile(message, .error)
    }

    private func writeToFile(_ msg: String, _ type: OSLogEntryLog.Level) {
        if !fileManager.fileExists(atPath: logDir) {
            try? fileManager.createDirectory(
                atPath: logDir,
                withIntermediateDirectories: false,
                attributes: nil
            )
        }

        if !fileManager.fileExists(atPath: logFile) {
            createFile(at: startOfDay)
        } else if let attributes = try? fileManager.attributesOfItem(atPath: logFile),
                  let creationDate = attributes[.creationDate] as? Date, creationDate < startOfDay
        {
            try? fileManager.removeItem(atPath: logFilePrev)
            try? fileManager.moveItem(atPath: logFile, toPath: logFilePrev)
            createFile(at: startOfDay)
        }

        let logEntry = "[\(dateFormatter.string(from: Date())) \(getLevel(type))] \(msg)\n"
        let data = logEntry.data(using: .utf8)!
        try? data.append(fileURL: URL(fileURLWithPath: logFile))
    }

    private var startOfDay: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var logFile: String {
        getDocumentsDirectory().appendingPathComponent("danakit/dana_log.txt").path
    }

    private var logDir: String {
        getDocumentsDirectory().appendingPathComponent("danakit").path
    }

    private var logFilePrev: String {
        getDocumentsDirectory().appendingPathComponent("danakit/dana_log_prev.txt").path
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }

    private func createFile(at date: Date) {
        fileManager.createFile(atPath: logFile, contents: nil, attributes: [.creationDate: date])
    }

    func getDebugLogs() -> [URL] {
        var items: [URL] = []

        if fileManager.fileExists(atPath: logFile) {
            items.append(URL(fileURLWithPath: logFile))
        }

        if fileManager.fileExists(atPath: logFilePrev) {
            items.append(URL(fileURLWithPath: logFilePrev))
        }

        return items
    }

    private func getLevel(_ type: OSLogEntryLog.Level) -> String {
        switch type {
        case .info:
            return "INFO"
        case .notice:
            return "WARNING"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        case .debug:
            return "DEBUG"
        default:
            return "UNKNOWN"
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
