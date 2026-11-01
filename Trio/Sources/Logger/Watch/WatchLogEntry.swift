import Foundation

struct WatchLogEntry: Codable, Sendable, Equatable {
    enum Level: String, Codable, Sendable, CaseIterable {
        case debug
        case info
        case warning
        case error
        case fault
    }

    enum Category: String, Codable, Sendable, CaseIterable {
        case connectivity
        case data
        case bolus
        case treatments
        case lifecycle

        var name: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    let seq: UInt64
    let date: Date
    let level: Level
    let category: Category
    let message: String
}

extension WatchLogEntry {
    static func jsonLines(_ entries: [WatchLogEntry]) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var data = Data()
        for entry in entries {
            guard let line = try? encoder.encode(entry) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        return data
    }

    // Lines that don't decode (torn writes, unknown levels or categories) are skipped
    static func entries(fromJSONLines data: Data) -> [WatchLogEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(WatchLogEntry.self, from: Data($0)) }
    }
}

enum WatchLogTransfer {
    static let marker = "trioWatchLog"
    static let version = 1
    static let firstSeq = "firstSeq"
    static let lastSeq = "lastSeq"
    static let watchBuild = "watchBuild"
    static let installID = "installID"
    static let created = "created"
    static let ack = "trioWatchLogAck"
    static let request = "trioWatchLogRequest"
    static let maxFileSize = 2_000_000
}
