import os.log
import os.signpost
import UIKit

var LoggerTestMode = false

private let baseReporter = TrioApp.resolver.resolve(GroupedIssueReporter.self)!

/// Moves logging off the calling thread and serializes the reporters.
/// Never `sync` onto it from work it runs.
private let loggerQueue = DispatchQueue(label: "Trio.loggerQueue", qos: .utility)

/// Writes all pending log lines to disk and returns once they are persisted.
func flushLogs() {
    loggerQueue.sync {}
    baseReporter.flush()
    SimpleLogReporter.flushWatchLog()
}

/// Runs `flushLogs()` off the calling thread, under a background task.
func flushLogsInBackgroundTask() {
    let application = UIApplication.shared
    let taskLock = NSLock(label: "Trio.flushLogsTaskLock")
    var taskID = UIBackgroundTaskIdentifier.invalid

    // Ends the task once, whether the flush finishes or the task expires first.
    func endTask() {
        let id: UIBackgroundTaskIdentifier = taskLock.perform {
            let id = taskID
            taskID = .invalid
            return id
        }
        guard id != .invalid else { return }
        DispatchQueue.main.async { application.endBackgroundTask(id) }
    }

    let startedID = application.beginBackgroundTask(withName: "Trio.flushLogs") { endTask() }
    taskLock.perform { taskID = startedID }

    DispatchQueue.global(qos: .utility).async {
        flushLogs()
        endTask()
    }
}

func debug(
    _ category: Logger.Category,
    _ message: @autoclosure () -> String,
    printToConsole: Bool = true,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    let msg = message()
    let date = Date()
    loggerQueue.async {
        category.logger.debug(msg, printToConsole: printToConsole, date: date, file: file, function: function, line: line)
    }
}

func info(
    _ category: Logger.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    let date = Date()
    loggerQueue.async {
        category.logger.info(message, date: date, file: file, function: function, line: line)
    }
}

func warning(
    _ category: Logger.Category,
    _ message: String,
    description: String? = nil,
    error maybeError: Swift.Error? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    let date = Date()
    loggerQueue.async {
        category.logger.warning(
            message,
            description: description,
            error: maybeError,
            date: date,
            file: file,
            function: function,
            line: line
        )
    }
}

func error(
    _ category: Logger.Category,
    _ message: String,
    description: String? = nil,
    error maybeError: Swift.Error? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) -> Never {
    // Get everything to disk before the process dies.
    let date = Date()
    loggerQueue.sync {
        category.logger.errorWithoutFatalError(
            message,
            description: description,
            error: maybeError,
            date: date,
            file: file,
            function: function,
            line: line
        )
    }
    baseReporter.flush()

    fatalError(
        "\(message) @ \(String(describing: description)) @ \(String(describing: maybeError)) @ \(file) @ \(function) @ \(line)"
    )
}

func check(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String,
    description: @autoclosure () -> String? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    guard !condition() else { return }
    let msg = message()
    let descr = description()
    warning(.default, msg, description: descr, file: file.file, function: function, line: line)
}

final class Logger {
    static let `default` = Logger(category: .default, reporter: baseReporter)
    static let service = Logger(category: .service, reporter: baseReporter)
    static let businessLogic = Logger(category: .businessLogic, reporter: baseReporter)
    static let openAPS = Logger(category: .openAPS, reporter: baseReporter)
    static let deviceManager = Logger(category: .deviceManager, reporter: baseReporter)
    static let apsManager = Logger(category: .apsManager, reporter: baseReporter)
    static let nightscout = Logger(category: .nightscout, reporter: baseReporter)
    static let remoteControl = Logger(category: .remoteControl, reporter: baseReporter)
    static let bolusState = Logger(category: .bolusState, reporter: baseReporter)
    static let watchManager = Logger(category: .watchManager, reporter: baseReporter)
    static let coreData = Logger(category: .coreData, reporter: baseReporter)
    static let storage = Logger(category: .storage, reporter: baseReporter)
    static let telemetry = Logger(category: .telemetry, reporter: baseReporter)

    enum Category: String {
        case `default`
        case service
        case businessLogic
        case openAPS
        case deviceManager
        case apsManager
        case nightscout
        case remoteControl
        case bolusState
        case watchManager
        case coreData
        case storage
        case telemetry

        var name: String {
            rawValue.capitalizingFirstLetter()
        }

        var logger: Logger {
            switch self {
            case .default: return .default
            case .service: return .service
            case .businessLogic: return .businessLogic
            case .openAPS: return .openAPS
            case .deviceManager: return .deviceManager
            case .apsManager: return .apsManager
            case .nightscout: return .nightscout
            case .remoteControl: return .remoteControl
            case .bolusState: return .bolusState
            case .watchManager: return .watchManager
            case .coreData: return .coreData
            case .storage: return .storage
            case .telemetry: return .telemetry
            }
        }

        fileprivate var log: OSLog {
            let subsystem = Bundle.main.bundleIdentifier!
            switch self {
            case .default: return OSLog.default
            case .apsManager,
                 .bolusState,
                 .businessLogic,
                 .coreData,
                 .deviceManager,
                 .nightscout,
                 .openAPS,
                 .remoteControl,
                 .service,
                 .storage,
                 .telemetry,
                 .watchManager:
                return OSLog(subsystem: subsystem, category: name)
            }
        }
    }

    fileprivate enum Error: Swift.Error {
        case error(String)
        case errorWithInnerError(String, Swift.Error)
        case errorWithDescription(String, String)
        case errorWithDescriptionAndInnerError(String, String, Swift.Error)

        private func domain() -> String {
            switch self {
            case let .error(domain),
                 let .errorWithDescription(domain, _),
                 let .errorWithDescriptionAndInnerError(domain, _, _),
                 let .errorWithInnerError(domain, _):
                return domain
            }
        }

        private func innerError() -> Swift.Error? {
            switch self {
            case let .errorWithDescriptionAndInnerError(_, _, error),
                 let .errorWithInnerError(_, error):
                return error
            default: return nil
            }
        }

        func asNSError() -> NSError {
            var info: [String: Any] = ["Description": String(describing: self)]

            if let error = innerError() {
                info["Error"] = String(describing: error)
            }

            return NSError(domain: domain(), code: -1, userInfo: info)
        }
    }

    private let category: Category
    private let reporter: IssueReporter
    let log: OSLog

    private init(category: Category, reporter: IssueReporter) {
        self.category = category
        self.reporter = reporter
        log = category.log
    }

    static func setup() {
        baseReporter.setup()
    }

    func debug(
        _ message: @autoclosure () -> String,
        printToConsole: Bool = true,
        date: Date = Date(),
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let message = "DEV: \(message())"
        if printToConsole {
            os_log("%@ - %@ - %d %{public}@", log: log, type: .debug, file.file, function, line, message)
        }
        reporter.log(category.name, message, date: date, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        date: Date = Date(),
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let printedMessage = "INFO: \(message)"
        os_log("%@ - %@ - %d %{public}@", log: log, type: .info, file.file, function, line, printedMessage)
        reporter.log(category.name, printedMessage, date: date, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        description: String? = nil,
        error maybeError: Swift.Error? = nil,
        date: Date = Date(),
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let loggerError = maybeError.loggerError(message: message, withDescription: description)
        let message = "WARN: \(String(describing: loggerError))"

        os_log("%@ - %@ - %d %{public}@", log: log, type: .default, file.file, function, line, message)
        reporter.log(category.name, message, date: date, file: file, function: function, line: line)
        if !LoggerTestMode, maybeError?.shouldReportNonFatalIssue ?? true {
            reporter.reportNonFatalIssue(withError: loggerError.asNSError())
        }
    }

    func error(
        _ message: String,
        description: String? = nil,
        error maybeError: Swift.Error? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) -> Never {
        errorWithoutFatalError(message, description: description, error: maybeError, file: file, function: function, line: line)
        reporter.flush()

        fatalError(
            "\(message) @ \(String(describing: description)) @ \(String(describing: maybeError)) @ \(file) @ \(function) @ \(line)"
        )
    }

    fileprivate func errorWithoutFatalError(
        _ message: String,
        description: String? = nil,
        error maybeError: Swift.Error? = nil,
        date: Date = Date(),
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        let loggerError = maybeError.loggerError(message: message, withDescription: description)
        let message = "ERR: \(String(describing: loggerError))"

        os_log("%@ - %@ - %d %{public}@", log: log, type: .error, file.file, function, line, message)
        reporter.log(category.name, message, date: date, file: file, function: function, line: line)
        reporter.reportNonFatalIssue(withError: loggerError.asNSError())
    }
}

private extension Optional where Wrapped == Swift.Error {
    func loggerError(message: String, withDescription description: String?) -> Logger.Error {
        switch (description, self) {
        case (nil, nil):
            return .error(message)
        case let (descr?, nil):
            return .errorWithDescription(message, descr)
        case let (nil, error?):
            return .errorWithInnerError(message, error)
        case let (descr?, error?):
            return .errorWithDescriptionAndInnerError(message, descr, error)
        }
    }
}

private extension String {
    var file: String { components(separatedBy: "/").last ?? "" }
}
