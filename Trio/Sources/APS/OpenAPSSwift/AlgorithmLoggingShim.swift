import Foundation

// MARK: - Package-only logging shim

//
// This file exists solely for the `Trio` SPM target declared in
// `AlgorithmPackage/Package.swift`, which compiles the oref algorithm (plus its
// models) as a standalone macOS-capable module so `swift test` can run the
// algorithm suite without building the iOS app or booting a simulator.
//

#if TRIO_ALGORITHM_PACKAGE

    /// Stands in for the app's `Logger` so `Logger.Category` resolves in the package.
    enum Logger {
        /// Mirrors `Logger.Category` in the app target.
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

    /// Set by a test to capture algorithm log output; defaults to discarding it.
    nonisolated(unsafe) var algorithmLogSink: ((Logger.Category, String) -> Void)?

    func debug(
        _ category: Logger.Category,
        _ message: @autoclosure () -> String,
        printToConsole _: Bool = true,
        file _: String = #file,
        function _: String = #function,
        line _: UInt = #line
    ) {
        algorithmLogSink?(category, message())
    }

    func info(
        _ category: Logger.Category,
        _ message: String,
        file _: String = #file,
        function _: String = #function,
        line _: UInt = #line
    ) {
        algorithmLogSink?(category, message)
    }

    func warning(
        _ category: Logger.Category,
        _ message: String,
        description _: String? = nil,
        error _: Swift.Error? = nil,
        file _: String = #file,
        function _: String = #function,
        line _: UInt = #line
    ) {
        algorithmLogSink?(category, message)
    }

#endif
