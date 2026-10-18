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
    let message = String(describing: maybeError.loggerError(message: message, withDescription: description))
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
    let message = String(describing: maybeError.loggerError(message: message, withDescription: description))
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
    let message = String(describing: maybeError.loggerError(message: message, withDescription: description))
    TrioLogger.log(.fault, category, message, file: file, function: function, line: line)
}

enum Logger {
    enum Category: String, CaseIterable {
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
    }

    fileprivate enum Error: Swift.Error {
        case error(String)
        case errorWithInnerError(String, Swift.Error)
        case errorWithDescription(String, String)
        case errorWithDescriptionAndInnerError(String, String, Swift.Error)
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
