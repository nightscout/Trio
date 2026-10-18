import Foundation
import os

enum TrioLogger {
    private struct State: Sendable {
        var sink: any LogSink
        var installed: Bool
    }

    private static let earlySink = InMemoryLogSink()
    private static let state = OSAllocatedUnfairLock(initialState: State(sink: earlySink, installed: false))

    static var sink: any LogSink {
        state.withLock { $0.sink }
    }

    static func install(_ sink: any LogSink) {
        state.withLock { state in
            // Replay records logged before the first install so they still reach the real sink.
            if !state.installed {
                earlySink.snapshot().forEach(sink.accept)
            }
            state.sink = sink
            state.installed = true
        }
    }

    static func log(
        _ level: LogLevel,
        _ category: Logger.Category,
        _ message: String,
        printToConsole: Bool = true,
        file: String,
        function: String,
        line: UInt
    ) {
        let record = LogRecord(
            timestamp: Date(),
            level: level,
            category: category.name,
            message: message,
            file: file.lastPathComponentFast,
            function: function,
            line: line,
            launchID: LaunchID.current
        )
        if printToConsole {
            category.osLogger.log(
                level: level.osLogType,
                "\(record.file, privacy: .public) - \(function, privacy: .public) - \(line) \(level.linePrefix, privacy: .public)\(message, privacy: .public)"
            )
        }
        sink.accept(record)
    }
}

extension Logger.Category {
    private static let osLoggers: [Logger.Category: os.Logger] = {
        let subsystem = Bundle.main.bundleIdentifier ?? "org.nightscout.Trio"
        return Dictionary(uniqueKeysWithValues: allCases.map { ($0, os.Logger(subsystem: subsystem, category: $0.name)) })
    }()

    var osLogger: os.Logger {
        Self.osLoggers[self] ?? os.Logger()
    }
}

private extension String {
    var lastPathComponentFast: String {
        guard let slash = lastIndex(of: "/") else { return self }
        return String(self[index(after: slash)...])
    }
}
