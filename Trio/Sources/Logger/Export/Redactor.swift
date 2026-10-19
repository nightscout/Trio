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

    private static let minimumExactLength = 4

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
