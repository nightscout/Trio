import Foundation

/// After the port from Javascript to Swift is complete, we should remove the logging module:
/// https://github.com/nightscout/Trio-dev/issues/293

/// Represents an exception that occurred during algorithm execution
struct AlgorithmException: Codable {
    let message: String
    let stackTrace: String?
    let errorType: String?

    init(message: String, stackTrace: String? = nil, errorType: String? = nil) {
        self.message = message
        self.stackTrace = stackTrace
        self.errorType = errorType
    }

    init(error: Error) {
        // Get the error message
        if let localizedError = error as? LocalizedError {
            message = localizedError.errorDescription ?? error.localizedDescription
        } else {
            message = error.localizedDescription
        }

        // Get error type
        errorType = String(describing: type(of: error))

        // Get stack trace if available
        if let nsError = error as NSError? {
            var traceComponents: [String] = []

            // Add domain and code
            traceComponents.append("Domain: \(nsError.domain)")
            traceComponents.append("Code: \(nsError.code)")

            // Add userInfo details
            if !nsError.userInfo.isEmpty {
                traceComponents.append("UserInfo: \(nsError.userInfo)")
            }

            // Add call stack
            let callStackSymbols = Thread.callStackSymbols as [String]
            if !callStackSymbols.isEmpty {
                traceComponents.append("Call Stack:")
                traceComponents.append(contentsOf: callStackSymbols)
            }

            stackTrace = traceComponents.isEmpty ? nil : traceComponents.joined(separator: "\n")
        } else {
            stackTrace = nil
        }
    }
}

/// Represents the type of comparison result
enum ComparisonResultType: String, Codable {
    case matching // Both implementations succeed with matching results
    case valueDifference // Both implementations succeed but values differ
    case matchingExceptions // Both implementations threw exceptions
    case jsOnlyException // Only JS threw an exception
    case swiftOnlyException // Only Swift threw an exception
    case comparisonError // The comparison algorithm itself failed
}

/// Represents a complete comparison between JS and Swift implementations
struct AlgorithmComparison: Codable {
    let id: UUID
    let createdAt: Date
    let function: OrefFunction
    let resultType: ComparisonResultType

    // Performance metrics (optional as they may not be available in error cases)
    let jsDuration: TimeInterval?
    let swiftDuration: TimeInterval?

    // Value differences (present when resultType is .valueDifference)
    let differences: [String: ValueDifference]?

    // Exception information (present for various error cases)
    let jsException: AlgorithmException?
    let swiftException: AlgorithmException?
    let comparisonError: AlgorithmException?

    init(
        function: OrefFunction,
        resultType: ComparisonResultType,
        jsDuration: TimeInterval? = nil,
        swiftDuration: TimeInterval? = nil,
        differences: [String: ValueDifference]? = nil,
        jsException: AlgorithmException? = nil,
        swiftException: AlgorithmException? = nil,
        comparisonError: AlgorithmException? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.function = function
        self.resultType = resultType
        self.jsDuration = jsDuration
        self.swiftDuration = swiftDuration
        self.differences = differences
        self.jsException = jsException
        self.swiftException = swiftException
        self.comparisonError = comparisonError
    }
}
