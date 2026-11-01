import Foundation

func debug(
    _ category: Logger.Category,
    _ message: @autoclosure () -> String,
    printToConsole: Bool = true,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    TrioLogger.log(.debug, category, message(), printToConsole: printToConsole, file: file, function: function, line: line)
}

func info(
    _ category: Logger.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    TrioLogger.log(.info, category, message, file: file, function: function, line: line)
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
    let message = composed(message, description: description, error: maybeError)
    TrioLogger.log(.warning, category, message, file: file, function: function, line: line)
}

func error(
    _ category: Logger.Category,
    _ message: String,
    description: String? = nil,
    error maybeError: Swift.Error? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    let message = composed(message, description: description, error: maybeError)
    TrioLogger.log(.error, category, message, file: file, function: function, line: line)
}

func fault(
    _ category: Logger.Category,
    _ message: String,
    description: String? = nil,
    error maybeError: Swift.Error? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    let message = composed(message, description: description, error: maybeError)
    TrioLogger.log(.fault, category, message, file: file, function: function, line: line)
}

enum Logger {
    enum Category: String, CaseIterable {
        case loop
        case algorithm
        case pump
        case cgm
        case bolus
        case treatments
        case nightscout
        case tidepool
        case remote
        case healthKit
        case alerts
        case watch
        case liveActivity
        case storage
        case settings
        case telemetry
        case ui
        case lifecycle

        var name: String {
            rawValue.capitalizingFirstLetter()
        }
    }
}

private func composed(_ message: String, description: String?, error: Swift.Error?) -> String {
    [message, description, error.map { String(describing: $0) }].compactMap { $0 }.joined(separator: ": ")
}
