import Foundation
import Testing
@testable import Trio

class BundleReference {}

/// This test suite is to help us debug and verify iob errors from Trio devices
///
/// There are two key components. First, we have a version of the Javascript that has a number
/// of bugs fixed. We don't want to fix the real Javascript, so we put this fixed Javascript in the
/// testing bundle and use it to run comparisons. If the error we see in the field is one that we know
/// about and have fixed in JS, the Swift and JS implementations will produce the same results. You
/// can find the fixed JS here:
///  https://github.com/kingst/trio-oref/tree/tcd-fixes-for-swift-comparison
///
/// Second, we have a server that runs (part of `trio-oref-logs`) to serve error logs captured
/// from the field. This server needs to run on the same machine as the simulator where this test runs.
/// You can find more information about it from the `trio-oref-logs` repo.
@Suite("IoB using real pump history JSON", .serialized) struct IobJsonTests {
    private var originalTZ: String? = ProcessInfo.processInfo.environment["TZ"]

    // Helper function to set timezone
    private func setTimezone(identifier: String) {
        setenv("TZ", identifier, 1)
        tzset() // Make the change take effect
    }

    // Helper function to reset timezone
    private func resetTimezone() {
        // Restore system timezone
        if let originalTZ = originalTZ {
            setenv("TZ", originalTZ, 1)
        } else {
            unsetenv("TZ")
        }
        tzset()
    }

    // Note: This test case has a memory leak so limit your inputs
    // to about 250 files at a time
    @Test(
        "should produce same results for fixed JS and different for bundle JS",
        .enabled(if: false)
    ) func replayErrorInputs() async throws {
        let url = URL(string: "http://localhost:8123/list")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let files = try JSONDecoder().decode([String].self, from: data)
        let fileDataDecoder = JSONDecoder()
        fileDataDecoder.dateDecodingStrategy = .secondsSince1970
        for filePath in files {
            let dataUrl = URL(string: "http://localhost:8123\(filePath)")!
            let (data, _) = try await URLSession.shared.data(from: dataUrl)
            let algorithmComparison = try fileDataDecoder.decode(AlgorithmComparison.self, from: data)
            print("Checking \(filePath) @ \(algorithmComparison.createdAt)")
            guard let iobInputs = algorithmComparison.iobInput else {
                print("Skipping, no iobInputs found")
                if let str = algorithmComparison.comparisonError {
                    print(str)
                }
                if let str = algorithmComparison.swiftException {
                    print(str)
                }
                continue
            }

            setTimezone(identifier: algorithmComparison.timezone)

            try await checkFixedJsAgainstSwift(iobInputs: algorithmComparison.iobInput!)
            try await checkBundleJsAgainstSwift(iobInputs: algorithmComparison.iobInput!)

            resetTimezone()
        }
    }

    func checkFixedJsAgainstSwift(iobInputs: IobInputs) async throws {
        let openAps = OpenAPSFixed()
        let (iobResultSwift, _) = OpenAPSSwift.iob(
            pumphistory: iobInputs.history,
            profile: try JSONBridge.to(iobInputs.profile),
            clock: iobInputs.clock,
            autosens: try JSONBridge.to(iobInputs.autosens)
        )

        let iobResultJavascript = await openAps.iobJavascript(
            pumphistory: iobInputs.history,
            profile: try JSONBridge.to(iobInputs.profile),
            clock: iobInputs.clock,
            autosens: try JSONBridge.to(iobInputs.autosens)
        )

        let comparison = JSONCompare.createComparison(
            function: .iob,
            swift: iobResultSwift,
            swiftDuration: 0.1,
            javascript: iobResultJavascript,
            javascriptDuration: 0.1,
            iobInputs: nil
        )

        if comparison.resultType == .valueDifference {
            print(comparison.differences!.prettyPrintedJSON!)
        }

        if comparison.resultType != .matching {
            print("REPLAY ERROR: Fixed JS didn't match")
        }

        #expect(comparison.resultType == .matching)
    }

    func checkBundleJsAgainstSwift(iobInputs: IobInputs) async throws {
        let openAps = OpenAPS(storage: BaseFileStorage(), tddStorage: MockTDDStorage())
        let (iobResultSwift, _) = OpenAPSSwift.iob(
            pumphistory: iobInputs.history,
            profile: try JSONBridge.to(iobInputs.profile),
            clock: iobInputs.clock,
            autosens: try JSONBridge.to(iobInputs.autosens)
        )

        let iobResultJavascript = await openAps.iobJavascript(
            pumphistory: iobInputs.history,
            profile: try JSONBridge.to(iobInputs.profile),
            clock: iobInputs.clock,
            autosens: try JSONBridge.to(iobInputs.autosens)
        )

        let comparison = JSONCompare.createComparison(
            function: .iob,
            swift: iobResultSwift,
            swiftDuration: 0.1,
            javascript: iobResultJavascript,
            javascriptDuration: 0.1,
            iobInputs: nil
        )

        if comparison.resultType != .valueDifference {
            print("REPLAY ERROR: bundle JS did't produce value difference")
        }

        #expect(comparison.resultType == .valueDifference)
    }

    /// simple utility for creating inputs for Javascript for use in testing
    @Test("format inputs for Javascript", .enabled(if: false)) func generateJavascriptInputs() throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "iob-error-log", ofType: "json")!
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let algorithmComparison = try decoder.decode(AlgorithmComparison.self, from: data)
        let iobInputs = algorithmComparison.iobInput!

        let encoder = JSONCoding.encoder
        let output = try encoder.encode(iobInputs)

        let sharedDir = FileManager.default.temporaryDirectory
        let outputURL = sharedDir.appendingPathComponent("js_iob_input_error.json")

        // Print the path so you can find it
        print("Writing to: \(outputURL.path)")

        try output.write(to: outputURL)

        let treatments = try IobHistory.calcTempTreatments(
            history: iobInputs.history.map { $0.computedEvent() },
            profile: iobInputs.profile,
            clock: iobInputs.clock,
            autosens: iobInputs.autosens,
            zeroTempDuration: nil
        )

        let treatmentsOut = try encoder.encode(treatments)
        let treatmentsUrl = sharedDir.appendingPathComponent("treatments.json")

        print("Writing to: \(treatmentsUrl.path)")

        try treatmentsOut.write(to: treatmentsUrl)
    }
}
