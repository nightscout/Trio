import Foundation

final class LegacyFileLogSink: LogSink {
    func accept(_: LogRecord) {}

    func flush() async {}

    func records(in _: DateInterval, minimumLevel _: LogLevel) async -> [LogRecord] {
        []
    }
}
