import Foundation

struct AppLogSection: DiagnosticReportSection {
    let title = "App log"
    let order = 90
    let includeDebug: Bool
    var sink: () -> any LogSink = { TrioLogger.sink }
    var legacyDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("logs", isDirectory: true)

    static let legacyFiles = ["log.txt", "log_prev.txt", "watch_log.txt"]
    private static let markdownLimit = 200

    func render(window: DateInterval, into directory: URL) async -> String {
        let sink = self.sink()
        await sink.flush()
        let minimumLevel: LogLevel = includeDebug ? .debug : .info
        let records = await sink.records(in: window, minimumLevel: minimumLevel).sorted { $0.timestamp < $1.timestamp }

        var notes = ["\(records.count) records at \(minimumLevel) and above in AppLog.txt."]
        do {
            try write(records, to: directory.appendingPathComponent("AppLog.txt"))
        } catch {
            notes.append("AppLog.txt could not be written: \(error.localizedDescription)")
        }
        let copied = copyLegacyFiles(into: directory)
        if !copied.isEmpty {
            notes.append("Older text logs: \(copied.joined(separator: ", ")).")
        }

        let warnings = records.filter { $0.level >= .warning }.suffix(Self.markdownLimit).map(Self.line)
        guard !warnings.isEmpty else { return (notes + ["", "_No warnings or errors in window_"]).joined(separator: "\n") }
        let tail = [
            "",
            "Last \(warnings.count) warnings and errors:",
            "",
            ReportFormatting.fenced(warnings.joined(separator: "\n"))
        ]
        return (notes + tail).joined(separator: "\n")
    }

    static func line(_ record: LogRecord) -> String {
        "\(ReportFormatting.timestamp(record.timestamp)) [\(String(describing: record.level).uppercased())] [\(record.category)] \(record.file):\(record.line) \(record.function) - \(record.message)"
    }

    private func write(_ records: [LogRecord], to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var start = 0
        while start < records.count {
            let end = min(start + 1000, records.count)
            let chunk = records[start ..< end].map { Self.line($0) + "\n" }.joined()
            try handle.write(contentsOf: Data(chunk.utf8))
            start = end
        }
    }

    private func copyLegacyFiles(into directory: URL) -> [String] {
        Self.legacyFiles.compactMap { name in
            let source = legacyDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }
            let target = "Legacy-\(name)"
            do {
                try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(target))
                return target
            } catch {
                warning(.service, "Could not copy \(name) into the report: \(error)")
                return nil
            }
        }
    }
}
