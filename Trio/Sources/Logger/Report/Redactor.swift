import Foundation

final class Redactor {
    enum Kind: String {
        case url
        case host
        case secret
        case device
        case email
        case pumpSerial = "pump-serial"
        case cgmSerial = "cgm-serial"
        case serial
    }

    struct ExactValue: Equatable {
        let value: String
        let kind: Kind
    }

    static let textExtensions: Set<String> = ["md", "txt", "json", "log", "csv"]
    private static let minimumExactLength = 4
    private static let chunkSize = 1 << 20

    private let exactValues: [ExactValue]
    private let patterns: [RedactionPatterns.Pattern]
    private var placeholders: [String: String] = [:]
    private var counters: [Kind: Int] = [:]

    init(exactValues: [ExactValue], patterns: [RedactionPatterns.Pattern] = RedactionPatterns.all) {
        var seen = Set<String>()
        self.exactValues = exactValues
            .map { ExactValue(value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines), kind: $0.kind) }
            .filter { $0.value.count >= Self.minimumExactLength && seen.insert($0.value.lowercased()).inserted }
            .sorted { $0.value.count > $1.value.count }
        self.patterns = patterns
    }

    func redact(_ text: String) -> String {
        var result = text
        for exact in exactValues where result.range(of: exact.value, options: .caseInsensitive) != nil {
            result = result.replacingOccurrences(
                of: exact.value,
                with: placeholder(for: exact.value, kind: exact.kind),
                options: .caseInsensitive
            )
        }
        for pattern in patterns {
            result = apply(pattern, to: result)
        }
        return result
    }

    // Rewrites text files in place and removes anything that cannot be redacted
    func redactFiles(in directory: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        else { return }
        // Collect first so the temporary rewrite files are never enumerated
        let urls = enumerator.allObjects.compactMap { $0 as? URL }
        for url in urls {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard Self.textExtensions.contains(url.pathExtension.lowercased()) else {
                try fileManager.removeItem(at: url)
                continue
            }
            do {
                try redactFile(at: url)
            } catch {
                warning(.service, "Could not redact \(url.lastPathComponent), leaving it out: \(error)")
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
        }
    }

    func redactFile(at url: URL) throws {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let output = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).redacting")
        guard fileManager.createFile(atPath: output.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: output.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            var start = data.startIndex
            while start < data.endIndex {
                // Patterns never span lines, so chunks end on a newline
                var end = min(start + Self.chunkSize, data.endIndex)
                if end < data.endIndex {
                    end = data[end...].firstIndex(of: 0x0A).map { $0 + 1 } ?? data.endIndex
                }
                let chunk = String(decoding: data[start ..< end], as: UTF8.self)
                try handle.write(contentsOf: Data(redact(chunk).utf8))
                start = end
            }
            try fileManager.removeItem(at: url)
            try fileManager.moveItem(at: output, to: url)
        } catch {
            try? fileManager.removeItem(at: output)
            throw error
        }
    }

    private func apply(_ pattern: RedactionPatterns.Pattern, to text: String) -> String {
        let source = text as NSString
        let matches = pattern.regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }
        var output = ""
        var cursor = 0
        for match in matches {
            let range = match.range(at: pattern.group)
            guard range.location != NSNotFound, range.location >= cursor else { continue }
            let value = source.substring(with: range)
            guard !RedactionPatterns.ignoredValues.contains(value.lowercased()) else { continue }
            output += source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            output += placeholder(for: value, kind: pattern.kind)
            cursor = range.location + range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    private func placeholder(for value: String, kind: Kind) -> String {
        let key = "\(kind.rawValue)|\(value.lowercased())"
        if let existing = placeholders[key] { return existing }
        let next = (counters[kind] ?? 0) + 1
        counters[kind] = next
        let placeholder = "<\(kind.rawValue)-\(next)>"
        placeholders[key] = placeholder
        return placeholder
    }
}
