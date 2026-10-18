import Foundation

enum AppLogTextExporter {
    static let fileName = "AppLog.txt"
    static let legacyFileNames = ["log.txt", "log_prev.txt", "watch_log.txt"]
    private static let sliceDuration: TimeInterval = 6 * 60 * 60

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func line(for record: LogRecord) -> String {
        "\(timestampFormatter.string(from: record.timestamp)) [\(record.level.label)] [\(record.category)] \(record.file):\(record.line) \(record.function) - \(record.message)\n"
    }

    static func write(records: [LogRecord], to url: URL) throws {
        let handle = try createFile(at: url)
        defer { try? handle.close() }
        try append(records, to: handle)
    }

    static func export(
        from store: AppLogStore,
        window: DateInterval,
        minimumLevel: LogLevel = .debug,
        into directory: URL
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let handle = try createFile(at: directory.appendingPathComponent(fileName))
        defer { try? handle.close() }

        var start = window.start
        while true {
            let end = min(start.addingTimeInterval(sliceDuration), window.end)
            let isLast = end >= window.end
            let records = await store.records(in: DateInterval(start: start, end: end), minimumLevel: minimumLevel)
            // Slice ends are inclusive; leave boundary records to the next slice
            try append(isLast ? records : records.filter { $0.timestamp < end }, to: handle)
            if isLast { break }
            start = end
        }

        for name in legacyFileNames {
            let source = store.directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent("Legacy-\(name)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static func createFile(at url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return try FileHandle(forWritingTo: url)
    }

    private static func append(_ records: [LogRecord], to handle: FileHandle) throws {
        var buffer = Data()
        for record in records {
            buffer.append(contentsOf: line(for: record).utf8)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
    }
}

extension LogLevel {
    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }

    var linePrefix: String {
        switch self {
        case .debug: return "DEV: "
        case .info: return "INFO: "
        case .notice: return "NOTICE: "
        case .warning: return "WARN: "
        case .error: return "ERR: "
        case .fault: return "FAULT: "
        }
    }
}
