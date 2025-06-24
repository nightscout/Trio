import Foundation
import Testing
@testable import Trio

@Suite("Meal testing using JSON inputs", .serialized) struct MealJsonTests {
    let timeZoneForTests = TimeZoneForTests()

    @Test(
        "Meal should produce same results for fixed JS",
        .enabled(if: false)
    ) func replayErrorInputs() async throws {
        // Note: This test case can only test one timezone per invocation
        // so you need to manually change this to try out errors from
        // different timezones
        let testingTimezone = "Europe/Berlin"
        let files = try await HttpFiles.listFiles()
        var skippedTimezones = Set<String>()
        for filePath in files {
            let algorithmComparison = try await HttpFiles.downloadFile(at: filePath)
            print("Checking \(filePath) @ \(algorithmComparison.createdAt)")
            guard algorithmComparison.timezone == testingTimezone else {
                print("Skipping timezone \(algorithmComparison.timezone)")
                skippedTimezones.insert(algorithmComparison.timezone)
                continue
            }
            guard let mealInputs = algorithmComparison.mealInput else {
                print("Skipping, no mealInputs found")
                if let str = algorithmComparison.comparisonError {
                    print(str)
                }
                if let str = algorithmComparison.swiftException {
                    print(str)
                }
                continue
            }

            timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

            try await checkFixedJsAgainstSwift(mealInputs: mealInputs)
            print("Checked \(filePath) \(algorithmComparison.timezone)")
            timeZoneForTests.resetTimezone()
        }

        if skippedTimezones.isEmpty {
            print("Didn't skip any timezones")
        } else {
            print("Skipped timezones:")
            for timezone in skippedTimezones {
                print("  - \(timezone)")
            }
        }
    }

    func checkFixedJsAgainstSwift(mealInputs: MealInputs) async throws {
        let openAps = OpenAPSFixed()
        let (mealResultSwift, _) = OpenAPSSwift.meal(
            pumphistory: mealInputs.pumpHistory,
            profile: try JSONBridge.to(mealInputs.profile),
            basalProfile: mealInputs.basalProfile,
            clock: mealInputs.clock,
            carbs: mealInputs.carbs,
            glucose: mealInputs.glucose
        )

        let mealResultJavascript = await openAps.mealJavascript(
            pumphistory: mealInputs.pumpHistory,
            profile: try JSONBridge.to(mealInputs.profile),
            basalProfile: mealInputs.basalProfile,
            clock: mealInputs.clock,
            carbs: mealInputs.carbs,
            glucose: mealInputs.glucose
        )

        let comparison = JSONCompare.createComparison(
            function: .meal,
            swift: mealResultSwift,
            swiftDuration: 0.1,
            javascript: mealResultJavascript,
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

    @Test("Format meal inputs for running in JS", .enabled(if: false)) func formatInputs() async throws {
        let openAps = OpenAPSFixed()

        // this test is meant for one-off analysis so it's ok to hard code
        // a file, just make sure to _not_ check in updates to this to
        // avoid polluting our change logs
        let algorithmComparison = try await HttpFiles.downloadFile(at: "/files/7a8a377e-f483-46a5-adbb-290baa04801b.3.json")
        let mealInputs = algorithmComparison.mealInput!

        let encoder = JSONCoding.encoder
        let output = try encoder.encode(mealInputs)

        let sharedDir = FileManager.default.temporaryDirectory
        let outputURL = sharedDir.appendingPathComponent("meal_error_inputs.json")
        // Print the path so you can find it
        print("Writing to: \(outputURL.path)")
        try output.write(to: outputURL)

        timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

        let (mealResultSwift, _) = OpenAPSSwift.meal(
            pumphistory: mealInputs.pumpHistory,
            profile: try JSONBridge.to(mealInputs.profile),
            basalProfile: mealInputs.basalProfile,
            clock: mealInputs.clock,
            carbs: mealInputs.carbs,
            glucose: mealInputs.glucose
        )

        print("Swift result")
        switch mealResultSwift {
        case let .success(rawJson):
            print(rawJson)
        case let .failure(error):
            print(error.localizedDescription)
        }

        let mealResultJavascript = await openAps.mealJavascript(
            pumphistory: mealInputs.pumpHistory,
            profile: try JSONBridge.to(mealInputs.profile),
            basalProfile: mealInputs.basalProfile,
            clock: mealInputs.clock,
            carbs: mealInputs.carbs,
            glucose: mealInputs.glucose
        )

        print("Fixed JS result")
        switch mealResultJavascript {
        case let .success(rawJson):
            print(rawJson)
        case let .failure(error):
            print(error.localizedDescription)
        }

        timeZoneForTests.resetTimezone()
    }
}
