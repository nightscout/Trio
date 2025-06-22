import Foundation
import Testing
@testable import Trio

@Suite("Meal testing using JSON inputs", .serialized) struct MealJsonTests {
    let timeZoneForTests = TimeZoneForTests()

    @Test("Test against simulator inputs") func simulatorInputs() throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "meal-input-sim", ofType: "json")!
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        // this file stores an object with JSON encoded strings (so double encoded)
        let jsonInputs = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let pumpHistory = try JSONBridge.pumpHistory(from: jsonInputs["pumpHistory"] as! String)
        let profile = try JSONBridge.profile(from: jsonInputs["profile"] as! String)
        let basalProfile = try JSONBridge.basalProfile(from: jsonInputs["basalProfile"] as! String)
        let clock = try JSONBridge.clock(from: jsonInputs["clock"] as! String)

        let decoder = JSONCoding.decoder
        var jsonData = (jsonInputs["carbs"] as! String).data(using: .utf8)!
        let carbHistory: [CarbsEntry] = try decoder.decode([CarbsEntry].self, from: jsonData)

        jsonData = (jsonInputs["glucose"] as! String).data(using: .utf8)!
        let glucoseHistory: [BloodGlucose] = try decoder.decode([BloodGlucose].self, from: jsonData)

        jsonData = (jsonInputs["meal"] as! String).data(using: .utf8)!
        let mealResultFromJs = try decoder.decode(ComputedCarbs.self, from: jsonData)

        let mealResult = try MealGenerator.generate(
            pumpHistory: pumpHistory,
            profile: profile,
            basalProfile: basalProfile,
            clock: clock,
            carbHistory: carbHistory,
            glucoseHistory: glucoseHistory
        )

        #expect(mealResult?.mealCOB == mealResultFromJs.mealCOB)
        #expect(mealResult?.carbs == mealResultFromJs.carbs)
        #expect(mealResult?.currentDeviation == mealResultFromJs.currentDeviation)
        // https://github.com/nightscout/Trio-dev/issues/539
        // Ignore this check due to Issue 539
        // #expect(mealResult?.allDeviations == mealResultFromJs.allDeviations)
        #expect(mealResult?.maxDeviation == mealResultFromJs.maxDeviation)
        #expect(mealResult?.slopeFromMaxDeviation == mealResultFromJs.slopeFromMaxDeviation)
        #expect(mealResult?.minDeviation == mealResultFromJs.minDeviation)
        #expect(mealResult!.slopeFromMinDeviation.isWithin(0.01, of: mealResultFromJs.slopeFromMinDeviation))
    }

    @Test(
        "Meal should produce same results for fixed JS",
        .enabled(if: true)
    ) func replayErrorInputs() async throws {
        let files = try await HttpFiles.listFiles()
        for filePath in files {
            let algorithmComparison = try await HttpFiles.downloadFile(at: filePath)
            print("Checking \(filePath) @ \(algorithmComparison.createdAt)")
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

            timeZoneForTests.resetTimezone()
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
            mealInputs: nil
        )

        if comparison.resultType == .valueDifference {
            print(comparison.differences!.prettyPrintedJSON!)
        }

        if comparison.resultType != .matching {
            print("REPLAY ERROR: Fixed JS didn't match")
        }

        #expect(comparison.resultType == .matching)
    }

    @Test("Format inputs for running in JS", .enabled(if: true)) func formatInputs() async throws {
        let openAps = OpenAPSFixed()

        // this test is meant for one-off analysis so it's ok to hard code
        // a file, just make sure to _not_ check in updates to this to
        // avoid polluting our change logs
        let algorithmComparison = try await HttpFiles.downloadFile(at: "/files/02273a81-c2ed-461b-8d4e-b9b085227f61.1.json")
        let mealInputs = algorithmComparison.mealInput!

        let encoder = JSONCoding.encoder
        let output = try encoder.encode(mealInputs)

        let sharedDir = FileManager.default.temporaryDirectory
        let outputURL = sharedDir.appendingPathComponent("meal_error_inputs.json")
        // Print the path so you can find it
        print("Writing to: \(outputURL.path)")
        try output.write(to: outputURL)

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
    }
}
