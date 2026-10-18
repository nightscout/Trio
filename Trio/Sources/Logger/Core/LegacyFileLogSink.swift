import Foundation

final class LegacyFileLogSink: LogSink, @unchecked Sendable {
    static var defaultDirectory: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("logs", isDirectory: true)
    }

    let directory: URL
    let fileURL: URL
    let previousFileURL: URL

    private let queue = DispatchQueue(label: "LegacyFileLogSink.queue", qos: .utility)
    private let fileManager = FileManager.default
    private let calendar = Calendar.current
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    // Only touched on `queue`.
    private var handle: FileHandle?
    private var handleDay: Date?

    init(directory: URL = LegacyFileLogSink.defaultDirectory) {
        self.directory = directory
        fileURL = directory.appendingPathComponent("log.txt")
        previousFileURL = directory.appendingPathComponent("log_prev.txt")
    }

    deinit {
        try? handle?.close()
    }

    func accept(_ record: LogRecord) {
        queue.async { self.write(record) }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    func records(in _: DateInterval, minimumLevel _: LogLevel) async -> [LogRecord] {
        []
    }

    private func write(_ record: LogRecord) {
        let startOfDay = calendar.startOfDay(for: record.timestamp)
        if handleDay != startOfDay {
            try? handle?.close()
            handle = openFile(startOfDay: startOfDay)
            handleDay = handle == nil ? nil : startOfDay
        }
        guard let handle else { return }

        let line =
            "\(formatter.string(from: record.timestamp)) [\(record.category)] \(record.file) - \(record.function) - \(record.line) - \(record.level.linePrefix)\(record.message)\n"
        do {
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            try? handle.close()
            self.handle = nil
            handleDay = nil
        }
    }

    private func openFile(startOfDay: Date) -> FileHandle? {
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let creationDate = attributes[.creationDate] as? Date, creationDate < startOfDay
            {
                try? fileManager.removeItem(at: previousFileURL)
                try? fileManager.moveItem(at: fileURL, to: previousFileURL)
                fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.creationDate: startOfDay])
            }
        } else {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.creationDate: startOfDay])
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }
}

extension LogLevel {
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
