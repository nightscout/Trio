import Foundation
import Testing
@testable import Trio

@Suite("Autosens using real JSON", .serialized) struct AutosensJsonTests {
    let timeZoneForTests = TimeZoneForTests()

    // static func from<T: Decodable>(string: String) throws -> T
    func loadJson<T: Decodable>(_ name: String) throws -> T {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: name, ofType: "json")!
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    @Test("Test with resistance") func generateJavascriptInputs() throws {
        let glucose: [BloodGlucose] = try loadJson("as-glucose")
        let pump: [PumpHistoryEvent] = try loadJson("as-pump")
        let basalProfile: [BasalProfileEntry] = try loadJson("as-basal")
        let profile: Profile = try loadJson("as-profile")
        let carbs: [CarbsEntry] = try loadJson("as-carbs")
        let tempTargets: [TempTarget] = try loadJson("as-temp-targets")

        let clock = Date("2025-06-08T00:14:35.481Z")!

        timeZoneForTests.setTimezone(identifier: "America/Los_Angeles")

        let autosensResult = try AutosensGenerator.generate(
            glucose: glucose,
            pumpHistory: pump,
            basalProfile: basalProfile,
            profile: profile,
            carbs: carbs,
            tempTargets: tempTargets,
            maxDeviations: 96,
            clock: clock,
            includeDeviationsForTesting: true
        )

        let deviationsUnsorted: [Decimal] = try loadJson("deviationsUnsorted")

        #expect(autosensResult.ratio == 1.2)
        #expect(autosensResult.newisf == 46)
        #expect(deviationsUnsorted.count == autosensResult.deviationsUnsorted?.count)

        for (ref, calc) in zip(deviationsUnsorted, autosensResult.deviationsUnsorted!) {
            // we can get differences due to rounding inconsistencies between
            // javascript and swift with negative numbers
            #expect(ref.isWithin(0.01, of: calc))
        }

        timeZoneForTests.resetTimezone()
    }

    func checkFixedJsAgainstSwift(autosensInputs: AutosensInputs) async throws {
        let openAps = OpenAPSFixed()
        let (autosensResultSwift, _) = OpenAPSSwift.autosense(
            glucose: autosensInputs.glucose,
            pumpHistory: autosensInputs.history,
            basalProfile: autosensInputs.basalProfile,
            profile: try JSONBridge.to(autosensInputs.profile),
            carbs: autosensInputs.carbs,
            tempTargets: autosensInputs.tempTargets,
            clock: autosensInputs.clock,
            includeDeviationsForTesting: true
        )

        let autosensResultJavascript = await openAps.autosenseJavascript(
            glucose: autosensInputs.glucose,
            pumpHistory: autosensInputs.history,
            basalprofile: autosensInputs.basalProfile,
            profile: try JSONBridge.to(autosensInputs.profile),
            carbs: autosensInputs.carbs,
            temptargets: autosensInputs.tempTargets,
            clock: autosensInputs.clock
        )

        let comparison = JSONCompare.createComparison(
            function: .autosens,
            swift: autosensResultSwift,
            swiftDuration: 0.1,
            javascript: autosensResultJavascript,
            javascriptDuration: 0.1,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil
        )

        if comparison.resultType == .valueDifference {
            print(comparison.differences!.prettyPrintedJSON!)
        }

        if comparison.resultType != .matching {
            print("REPLAY ERROR: Fixed JS didn't match")
            if case let .success(swiftJson) = autosensResultSwift, case let .success(jsJson) = autosensResultJavascript {
                try compareDeviations(swiftJson: swiftJson, jsJson: jsJson)
            }
        }

        #expect(comparison.resultType == .matching)
    }

    func compareDeviations(swiftJson: String, jsJson: String) throws {
        // Parse both JSON strings
        let swiftData = swiftJson.data(using: .utf8)!
        let jsData = jsJson.data(using: .utf8)!

        let swiftDict = try JSONSerialization.jsonObject(with: swiftData) as! [String: Any]
        let jsDict = try JSONSerialization.jsonObject(with: jsData) as! [String: Any]

        // Extract deviationsUnsorted arrays
        let swiftDeviations = swiftDict["deviationsUnsorted"] as! [Any]
        let jsDeviations = jsDict["deviationsUnsorted"] as! [Any]

        // Convert both to Double arrays
        let swiftDoubles = swiftDeviations.compactMap { value -> Double? in
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            return nil
        }

        let jsDoubles = jsDeviations.compactMap { value -> Double? in
            if let number = value as? NSNumber {
                return number.doubleValue
            } else if let string = value as? String {
                return Double(string)
            }
            return nil
        }

        // Compare the arrays
        print("Swift array count: \(swiftDoubles.count)")
        print("JS array count: \(jsDoubles.count)")

        guard swiftDoubles.count == jsDoubles.count else {
            print("Arrays have different lengths!")
            print("Swift: \(swiftDoubles)")
            print("JS: \(jsDoubles)")
            return
        }

        var differences: [(index: Int, swift: Double, js: Double)] = []

        for (index, (swiftVal, jsVal)) in zip(swiftDoubles, jsDoubles).enumerated() {
            if abs(swiftVal - jsVal) > 0.001 { // Small tolerance for floating point comparison
                differences.append((index: index, swift: swiftVal, js: jsVal))
            }
        }

        if differences.isEmpty {
            print("✅ Arrays are identical (within tolerance)")
        } else {
            print("❌ Found \(differences.count) differences:")
            for diff in differences {
                print("  Index \(diff.index): Swift=\(diff.swift), JS=\(diff.js)")
            }
        }
    }

    @Test(
        "should produce same results for autosens for fixed JS",
        .enabled(if: false)
    ) func replayErrorInputs() async throws {
        let files = try await HttpFiles.listFiles()
        for filePath in files {
            let algorithmComparison = try await HttpFiles.downloadFile(at: filePath)
            print("Checking \(filePath) @ \(algorithmComparison.createdAt)")
            guard let autosensInputs = algorithmComparison.autosensInput else {
                print("Skipping, no autosensInputs found")
                if let str = algorithmComparison.comparisonError {
                    print(str)
                }
                if let str = algorithmComparison.swiftException {
                    print(str)
                }
                continue
            }

            // remove this
            let encoder = JSONCoding.encoder
            var output = try encoder.encode(autosensInputs)
            var sharedDir = FileManager.default.temporaryDirectory
            var outputURL = sharedDir.appendingPathComponent("autosens_inputs.json")
            print("Writing to: \(outputURL.path)")
            try output.write(to: outputURL)

            timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

            try await checkFixedJsAgainstSwift(autosensInputs: autosensInputs)

            timeZoneForTests.resetTimezone()
        }
    }
}
