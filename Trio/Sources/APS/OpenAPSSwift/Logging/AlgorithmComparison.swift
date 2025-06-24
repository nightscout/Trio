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

/// For tracking inputs to IoB when there is a mismatch
struct IobInputs: Codable {
    let history: [PumpHistoryEvent]
    let profile: Profile
    let clock: Date
    let autosens: Autosens?
}

/// For tracking inputs to `meal` when there is a mismatch
struct MealInputs: Codable {
    let pumpHistory: [PumpHistoryEvent]
    let profile: Profile
    let basalProfile: [BasalProfileEntry]
    let clock: Date
    let carbs: [CarbsEntry]
    let glucose: [BloodGlucose]
}

/// For tracking inputs to Autosens when there is a mismatch
struct AutosensInputs: Codable {
    let glucose: [BloodGlucose]
    let history: [PumpHistoryEvent]
    let basalProfile: [BasalProfileEntry]
    let profile: Profile
    let carbs: [CarbsEntry]
    let tempTargets: [TempTarget]
    let clock: Date
}

/// For tracking inputs to `determineBasal` when there is a mismatch
struct DetermineBasalInputs: Codable {
    let glucose: [BloodGlucose]
    let currentTemp: TempBasal
    let iob: [IobResult]
    let profile: Profile
    let autosens: Autosens?
    let meal: ComputedCarbs?
    let microBolusAllowed: Bool
    let reservoir: Decimal?
    let pumpHistory: [PumpHistoryEvent]
    let preferences: Preferences
    let basalProfile: [BasalProfileEntry]
    let trioCustomOrefVariables: TrioCustomOrefVariables
    let clock: Date
}

/// Represents a complete comparison between JS and Swift implementations
struct AlgorithmComparison: Codable {
    let id: UUID
    let createdAt: Date
    let timezone: String
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
    let version: String?
    let isSimulator: Bool?
    let isDebugBuild: Bool?

    // Inputs for mismatches
    let iobInput: IobInputs?
    let mealInput: MealInputs?
    let autosensInput: AutosensInputs?
    let determineBasalInput: DetermineBasalInputs?

    init(
        function: OrefFunction,
        resultType: ComparisonResultType,
        jsDuration: TimeInterval? = nil,
        swiftDuration: TimeInterval? = nil,
        differences: [String: ValueDifference]? = nil,
        jsException: AlgorithmException? = nil,
        swiftException: AlgorithmException? = nil,
        comparisonError: AlgorithmException? = nil,
        iobInputs: IobInputs? = nil,
        mealInputs: MealInputs? = nil,
        autosensInputs: AutosensInputs? = nil,
        determineBasalInputs: DetermineBasalInputs? = nil,
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
        iobInput = iobInputs
        mealInput = mealInputs
        autosensInput = autosensInputs
        determineBasalInput = determineBasalInputs
        timezone = TimeZone.current.identifier
        version = "4"
        #if targetEnvironment(simulator)
            isSimulator = true
        #else
            isSimulator = false
        #endif

        #if DEBUG
            isDebugBuild = true
        #else
            isDebugBuild = false
        #endif
    }
}
