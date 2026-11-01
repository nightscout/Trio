import Foundation

final class Redactor {
    enum Kind: String {
        case nightscoutURL = "nightscout-url"
        case nightscoutHost = "nightscout-host"
        case apiSecret = "api-secret"
        case remoteSecret = "remote-secret"
        case pushToken = "push-token"
        case installID = "install-id"
        case secret
        case email
        case account
        case pumpSerial = "pump-serial"
        case cgmSerial = "cgm-serial"
        case device
        case remoteUser = "remote-user"

        // One value per install; the others are numbered per file
        var isSingular: Bool {
            switch self {
            case .apiSecret,
                 .installID,
                 .nightscoutHost,
                 .nightscoutURL,
                 .pushToken,
                 .remoteSecret: return true
            default: return false
            }
        }
    }

    struct ExactValue: Equatable {
        let value: String
        let kind: Kind
    }

    private struct Needle {
        let bytes: [UInt8]
        let kind: Kind
        let isWholeToken: Bool
    }

    private struct Match {
        let start: Int
        let end: Int
        let needle: Int
    }

    private struct InTransitRule {
        let marker: String
        let regex: NSRegularExpression
        let kind: Kind
    }

    static let minimumLength = 4

    // Values only ever seen in transit, never stored on this phone
    private static let inTransitRules: [InTransitRule] = [
        ("Command Type:", #"\bUser: ([^.\n]{1,64})\. Command Type:"#, Kind.remoteUser),
        ("Fleet secret:", #"Fleet secret: ([^\n]+)"#, Kind.secret)
    ].compactMap { marker, pattern, kind in
        (try? NSRegularExpression(pattern: pattern)).map { InTransitRule(marker: marker, regex: $0, kind: kind) }
    }

    private let needles: [Needle]
    private var placeholders: [String: String] = [:]
    private var counters: [Kind: Int] = [:]

    init(exactValues: [ExactValue]) {
        var seen = Set<[UInt8]>()
        needles = exactValues
            .map { (bytes: Array($0.value.trimmingCharacters(in: .whitespacesAndNewlines).utf8).map(Self.fold), kind: $0.kind) }
            .filter { $0.bytes.count >= Self.minimumLength && seen.insert($0.bytes).inserted }
            .sorted { $0.bytes.count > $1.bytes.count }
            .map {
                Needle(bytes: $0.bytes, kind: $0.kind, isWholeToken: $0.bytes.allSatisfy(Self.isHexDigit))
            }
    }

    func redact(_ text: String) -> String {
        var source = text
        // The standard library lowercases in bulk; per-byte folding is slow in unoptimized builds
        var lowered = text.lowercased()
        let (exact, markers) = source.withUTF8 { source in
            lowered.withUTF8 { lowered in
                guard lowered.count == source.count else {
                    return Self.fold(source).withUnsafeBufferPointer { scan(source, folded: $0) }
                }
                return scan(source, folded: lowered)
            }
        }
        var result = exact ?? text
        for (rule, present) in zip(Self.inTransitRules, markers) where present {
            result = apply(rule, to: result)
        }
        return result
    }

    private func scan(_ source: UnsafeBufferPointer<UInt8>, folded: UnsafeBufferPointer<UInt8>) -> (String?, [Bool]) {
        let markers = Self.inTransitRules.map { rule in
            Array(rule.marker.lowercased().utf8).withUnsafeBytes {
                memmem(folded.baseAddress, folded.count, $0.baseAddress, $0.count) != nil
            }
        }
        let matches = self.matches(in: folded, source: source)
        guard !matches.isEmpty else { return (nil, markers) }

        var output: [UInt8] = []
        output.reserveCapacity(source.count)
        var cursor = 0
        for match in matches {
            let needle = needles[match.needle]
            output.append(contentsOf: UnsafeBufferPointer(rebasing: source[cursor ..< match.start]))
            output.append(contentsOf: placeholder(for: String(decoding: needle.bytes, as: UTF8.self), kind: needle.kind).utf8)
            cursor = match.end
        }
        output.append(contentsOf: UnsafeBufferPointer(rebasing: source[cursor...]))
        return (String(decoding: output, as: UTF8.self), markers)
    }

    // Hex and decimal values match only as whole tokens so they never split a packet dump or a number
    private func matches(in folded: UnsafeBufferPointer<UInt8>, source: UnsafeBufferPointer<UInt8>) -> [Match] {
        guard let textStart = folded.baseAddress else { return [] }
        var found: [Match] = []
        for (index, needle) in needles.enumerated() {
            needle.bytes.withUnsafeBufferPointer { pattern in
                guard let patternStart = pattern.baseAddress else { return }
                var offset = 0
                while offset + pattern.count <= folded.count,
                      let hit = memmem(textStart + offset, folded.count - offset, patternStart, pattern.count)
                {
                    let start = UnsafeRawPointer(hit) - UnsafeRawPointer(textStart)
                    let end = start + pattern.count
                    let opens = start == 0 || !Self.isAlphanumeric(source[start - 1])
                    let closes = end == source.count || !Self.isAlphanumeric(source[end])
                    // Lowercasing may shift non-ASCII text, so confirm the hit against the original bytes
                    let same = (0 ..< pattern.count).allSatisfy { Self.fold(source[start + $0]) == pattern[$0] }
                    if same, !needle.isWholeToken || opens && closes {
                        found.append(Match(start: start, end: end, needle: index))
                    }
                    offset = start + 1
                }
            }
        }

        // Needles are sorted longest first, so the longest value wins at a shared start
        found.sort { ($0.start, $0.needle) < ($1.start, $1.needle) }
        var kept: [Match] = []
        var cursor = 0
        for match in found where match.start >= cursor {
            kept.append(match)
            cursor = match.end
        }
        return kept
    }

    private func apply(_ rule: InTransitRule, to text: String) -> String {
        let source = text as NSString
        var output = ""
        var cursor = 0
        for match in rule.regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let range = match.range(at: 1)
            output += source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            output += placeholder(for: source.substring(with: range), kind: rule.kind)
            cursor = range.location + range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    private func placeholder(for value: String, kind: Kind) -> String {
        if kind.isSingular { return "<\(kind.rawValue)>" }
        let key = "\(kind.rawValue)|\(value.lowercased())"
        if let existing = placeholders[key] { return existing }
        let next = (counters[kind] ?? 0) + 1
        counters[kind] = next
        let placeholder = "<\(kind.rawValue)-\(next)>"
        placeholders[key] = placeholder
        return placeholder
    }

    private static func fold(_ bytes: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        [UInt8](unsafeUninitializedCapacity: bytes.count) { buffer, count in
            for index in 0 ..< bytes.count {
                buffer[index] = fold(bytes[index])
            }
            count = bytes.count
        }
    }

    private static func fold(_ byte: UInt8) -> UInt8 {
        byte &- 0x41 < 26 ? byte | 0x20 : byte
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30 ... 0x39).contains(byte) || (0x61 ... 0x66).contains(byte)
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte)
    }
}
