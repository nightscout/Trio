import Foundation

struct LogLine {
    let date: Date
    let source: String
    let text: String
}

enum LogFileWriter {
    static let sliceDuration: TimeInterval = 6 * 60 * 60
    private static let bufferLimit = 64 * 1024

    static func timestampFormatter(milliseconds: Bool = true) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = milliseconds ? "yyyy-MM-dd HH:mm:ss.SSS Z" : "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }

    static func slices(of window: DateInterval) -> [DateInterval] {
        var slices: [DateInterval] = []
        var start = window.start
        repeat {
            let end = min(start.addingTimeInterval(sliceDuration), window.end)
            slices.append(DateInterval(start: start, end: end))
            start = end
        } while start < window.end
        return slices
    }

    static func write(
        header: String,
        window: DateInterval,
        to url: URL,
        redactor: Redactor,
        lines: (DateInterval) async -> [LogLine]
    ) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let formatter = timestampFormatter()

        var buffer = header + "\n== Log ==\n"
        func flush() throws {
            guard !buffer.isEmpty else { return }
            // Redact in bulk; per-line regex passes are too slow for 7 days of debug lines
            try handle.write(contentsOf: Data(redactor.redact(buffer).utf8))
            buffer.removeAll(keepingCapacity: true)
        }

        for slice in slices(of: window) {
            try Task.checkCancellation()
            let isLast = slice.end >= window.end
            let sorted = await lines(slice).enumerated()
                .filter { contains(slice, $0.element.date, isLast: isLast) }
                .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            for (_, line) in sorted {
                buffer += format(line, formatter: formatter)
                if buffer.utf8.count >= bufferLimit {
                    try flush()
                }
            }
            try flush()
        }
    }

    // Sources may return their inclusive slice end; it belongs to the next slice
    private static func contains(_ slice: DateInterval, _ date: Date, isLast: Bool) -> Bool {
        date >= slice.start && (date < slice.end || isLast && date == slice.end)
    }

    static func format(_ line: LogLine, formatter: DateFormatter) -> String {
        let text = line.text.replacingOccurrences(of: "\n", with: "\n    ")
        return "\(formatter.string(from: line.date)) \(line.source) \(text)\n"
    }
}
