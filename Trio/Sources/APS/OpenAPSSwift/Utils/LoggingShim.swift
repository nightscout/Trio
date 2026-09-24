#if TRIO_ALGORITHM_PACKAGE

    import Foundation
    import os

    /// Namespace matching the app `Logger.Category` so `.openAPS` resolves.
    enum Logger {
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
        }
    }

    private let osLogger = OSLog(subsystem: "org.nightscout.Trio.AlgorithmPackage", category: "TrioAlgorithm")

    func debug(
        _: Logger.Category,
        _ message: @autoclosure () -> String,
        printToConsole _: Bool = true,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        os_log(
            "%@ - %@ - %d %{public}@",
            log: osLogger,
            type: .debug,
            (file as NSString).lastPathComponent,
            function,
            line,
            message()
        )
    }

    func warning(
        _: Logger.Category,
        _ message: String,
        description _: String? = nil,
        error _: Swift.Error? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        os_log(
            "%@ - %@ - %d %{public}@",
            log: osLogger,
            type: .default,
            (file as NSString).lastPathComponent,
            function,
            line,
            message
        )
    }

#endif
