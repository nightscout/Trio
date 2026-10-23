import Foundation

protocol LogSink: Sendable {
    func accept(_ record: LogRecord)
    func flush() async
    func records(in window: DateInterval, minimumLevel: LogLevel) async -> [LogRecord]
}
