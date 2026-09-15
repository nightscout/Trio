import Foundation
import Testing
@testable import Trio

/// Local stand-in for TestError, which lives outside the directory AlgorithmPackage symlinks in.
struct ParityError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// The zone the goldens were recorded in. Pinned from outside the process — the scheme's
/// TZ variable, or the CI job env — because suites run in parallel and setenv/NSTimeZone.default
/// are process-global: mutating them mid-run races every other suite.
enum ParityEnv {
    static let timeZoneIdentifier = "Europe/Berlin"

    static var isPinned: Bool { TimeZone.current.identifier == timeZoneIdentifier }
}

/// Records and compares byte-exact golden fixtures for the oref-swift pipeline.
enum ParityHarness {
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["TRIO_RECORD_GOLDENS"] == "1"
    }

    static var goldensDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("goldens")
    }

    /// Canonical serialization: sorted keys so string comparison is stable.
    static func canonicalJSON(_ value: some Encodable) throws -> String {
        let encoder = JSONCoding.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ParityError("canonical encoding produced non-UTF8 data")
        }
        return string + "\n"
    }

    /// Replaces the volatile Determination UUID with a fixed one.
    static func normalizeDeterminationId(_ json: String) -> String {
        json.replacingOccurrences(
            of: #""id" : "[0-9A-Fa-f-]{36}""#,
            with: #""id" : "00000000-0000-0000-0000-000000000000""#,
            options: .regularExpression
        )
    }

    static func goldenURL(scenario: String, stage: String) -> URL {
        goldensDirectory
            .appendingPathComponent(scenario)
            .appendingPathComponent("\(stage).json")
    }

    /// Record mode writes the golden; compare mode asserts byte equality.
    static func check(
        _ actual: String,
        scenario: String,
        stage: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(
            TimeZone.current.identifier == ParityEnv.timeZoneIdentifier,
            "timezone must be pinned before running the pipeline",
            sourceLocation: sourceLocation
        )
        let url = goldenURL(scenario: scenario, stage: stage)
        if isRecording {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try actual.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let golden = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record(
                "missing golden \(scenario)/\(stage).json — record with TEST_RUNNER_TRIO_RECORD_GOLDENS=1",
                sourceLocation: sourceLocation
            )
            return
        }
        if actual != golden {
            let actualURL = url.deletingLastPathComponent().appendingPathComponent("actual-\(stage).json")
            try? actual.write(to: actualURL, atomically: true, encoding: .utf8)
            Issue.record(
                "parity violation in \(scenario)/\(stage): \(firstDivergence(golden: golden, actual: actual)) — actual written to \(actualURL.path)",
                sourceLocation: sourceLocation
            )
        }
    }

    private static func firstDivergence(golden: String, actual: String) -> String {
        let goldenLines = golden.components(separatedBy: "\n")
        let actualLines = actual.components(separatedBy: "\n")
        for index in 0 ..< min(goldenLines.count, actualLines.count)
            where goldenLines[index] != actualLines[index]
        {
            return "line \(index + 1): golden `\(goldenLines[index])` vs actual `\(actualLines[index])`"
        }
        return "line count \(goldenLines.count) vs \(actualLines.count)"
    }
}
