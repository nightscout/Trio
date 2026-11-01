import Foundation
import os.log

enum LogLevel: Int16, Codable, CaseIterable, Comparable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice,
             .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
}

struct LogRecord: Sendable, Codable, Equatable {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let file: String
    let function: String
    let line: UInt
    let launchID: UUID
}
