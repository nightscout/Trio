import Foundation
import Testing
@testable import Trio

@Suite("DetermineBasal testing using JSON inputs", .serialized) struct DetermineBasalJsonTests {
    let timeZoneForTests = TimeZoneForTests()

    @Test(
        "DetermineBasal should produce same results for fixed JS",
        .enabled(if: ReplayTests.enabled)
    ) func replayErrorInputs() async throws {
        // Note: This test case can only test one timezone per invocation
        // so you need to manually change this to try out errors from
        // different timezones
        let testingTimezone = ReplayTests.timezone
        let files = try await HttpFiles.listFiles()
        for filePath in files {
            let algorithmComparison = try await HttpFiles.downloadFile(at: filePath)
            print("Checking \(filePath) @ \(algorithmComparison.createdAt)")
            guard algorithmComparison.timezone == testingTimezone else {
                continue
            }
            guard let determineBasalInput = algorithmComparison.determineBasalInput else {
                print("Skipping, no determineBasalInput found")
                if let str = algorithmComparison.comparisonError {
                    print(str)
                }
                if let str = algorithmComparison.swiftException {
                    print(str)
                    #expect(Bool(false), "Swift exception on determine")
                }
                continue
            }

            timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

            try await checkFixedJsAgainstSwift(determineBasalInput: determineBasalInput)
            print("Checked \(filePath) \(algorithmComparison.timezone)")
            timeZoneForTests.resetTimezone()
        }
    }

    func checkFixedJsAgainstSwift(determineBasalInput: DetermineBasalInputs) async throws {
        let openAps = OpenAPSFixed()
        let (determineBasalResultSwift, _) = OpenAPSSwift.determineBasal(
            glucose: determineBasalInput.glucose,
            currentTemp: determineBasalInput.currentTemp,
            iob: try JSONBridge.to(determineBasalInput.iob),
            profile: try JSONBridge.to(determineBasalInput.profile),
            autosens: try JSONBridge.to(determineBasalInput.autosens),
            meal: try JSONBridge.to(determineBasalInput.meal),
            microBolusAllowed: determineBasalInput.microBolusAllowed,
            reservoir: determineBasalInput.reservoir ?? 0,
            pumpHistory: determineBasalInput.pumpHistory,
            preferences: determineBasalInput.preferences,
            basalProfile: determineBasalInput.basalProfile,
            trioCustomOrefVariables: determineBasalInput.trioCustomOrefVariables,
            clock: determineBasalInput.clock
        )

        let determineBasalResultJavascript = try await openAps.determineBasalJavascript(
            glucose: determineBasalInput.glucose,
            currentTemp: determineBasalInput.currentTemp,
            iob: try JSONBridge.to(determineBasalInput.iob),
            profile: try JSONBridge.to(determineBasalInput.profile),
            autosens: try JSONBridge.to(determineBasalInput.autosens),
            meal: try JSONBridge.to(determineBasalInput.meal),
            microBolusAllowed: determineBasalInput.microBolusAllowed,
            reservoir: determineBasalInput.reservoir ?? 0,
            pumpHistory: determineBasalInput.pumpHistory,
            preferences: determineBasalInput.preferences,
            basalProfile: determineBasalInput.basalProfile,
            trioCustomOrefVariables: determineBasalInput.trioCustomOrefVariables,
            clock: determineBasalInput.clock
        )

        let comparison = JSONCompare.createComparison(
            function: .determineBasal,
            swift: determineBasalResultSwift,
            swiftDuration: 0.1,
            javascript: determineBasalResultJavascript,
            javascriptDuration: 0.1,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        if comparison.resultType == .valueDifference {
            print(comparison.differences!.prettyPrintedJSON!)
        }

        if comparison.resultType != .matching {
            print("REPLAY ERROR: Fixed JS didn't match")
        }

        #expect(comparison.resultType == .matching)
    }

    @Test("Format determineBasal inputs for running in JS", .enabled(if: true)) func formatInputs() async throws {
        let openAps = OpenAPSFixed()

        // this test is meant for one-off analysis so it's ok to hard code
        // a file, just make sure to _not_ check in updates to this to
        // avoid polluting our change logs
        let algorithmComparison = try await HttpFiles.downloadFile(at: "/files/0341b91d-c75b-462b-b5a1-5aee9e973bc8.1.json")
        let determineBasalInput = algorithmComparison.determineBasalInput!

        let encoder = JSONCoding.encoder
        let output = try encoder.encode(determineBasalInput)

        let sharedDir = FileManager.default.temporaryDirectory
        let outputURL = sharedDir.appendingPathComponent("determine_basal_error_inputs.json")
        // Print the path so you can find it
        print("Writing to: \(outputURL.path)")
        try output.write(to: outputURL)

        timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

        let (determineBasalResultSwift, _) = OpenAPSSwift.determineBasal(
            glucose: determineBasalInput.glucose,
            currentTemp: determineBasalInput.currentTemp,
            iob: try JSONBridge.to(determineBasalInput.iob),
            profile: try JSONBridge.to(determineBasalInput.profile),
            autosens: try JSONBridge.to(determineBasalInput.autosens),
            meal: try JSONBridge.to(determineBasalInput.meal),
            microBolusAllowed: determineBasalInput.microBolusAllowed,
            reservoir: determineBasalInput.reservoir ?? 0,
            pumpHistory: determineBasalInput.pumpHistory,
            preferences: determineBasalInput.preferences,
            basalProfile: determineBasalInput.basalProfile,
            trioCustomOrefVariables: determineBasalInput.trioCustomOrefVariables,
            clock: determineBasalInput.clock
        )

        print("Swift result")
        switch determineBasalResultSwift {
        case let .success(rawJson):
            print(rawJson)
        case let .failure(error):
            print(error.localizedDescription)
        }

        let determineBasalResultJavascript = try await openAps.determineBasalJavascript(
            glucose: determineBasalInput.glucose,
            currentTemp: determineBasalInput.currentTemp,
            iob: try JSONBridge.to(determineBasalInput.iob),
            profile: try JSONBridge.to(determineBasalInput.profile),
            autosens: try JSONBridge.to(determineBasalInput.autosens),
            meal: try JSONBridge.to(determineBasalInput.meal),
            microBolusAllowed: determineBasalInput.microBolusAllowed,
            reservoir: determineBasalInput.reservoir ?? 0,
            pumpHistory: determineBasalInput.pumpHistory,
            preferences: determineBasalInput.preferences,
            basalProfile: determineBasalInput.basalProfile,
            trioCustomOrefVariables: determineBasalInput.trioCustomOrefVariables,
            clock: determineBasalInput.clock
        )

        print("Fixed JS result")
        switch determineBasalResultJavascript {
        case let .success(rawJson):
            print(rawJson)
        case let .failure(error):
            print(error.localizedDescription)
        }

        let comparison = JSONCompare.createComparison(
            function: .determineBasal,
            swift: determineBasalResultSwift,
            swiftDuration: 0.1,
            javascript: determineBasalResultJavascript,
            javascriptDuration: 0.1,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        if comparison.resultType == .valueDifference {
            print(comparison.differences!.prettyPrintedJSON!)
        }

        #expect(comparison.resultType == .matching)

        timeZoneForTests.resetTimezone()
    }
}
