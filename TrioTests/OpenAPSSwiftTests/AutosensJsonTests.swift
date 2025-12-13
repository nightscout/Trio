import Foundation
import Testing
@testable import Trio

@Suite("Autosens using real JSON", .serialized) struct AutosensJsonTests {
    let timeZoneForTests = TimeZoneForTests()

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

    func compareDeviations(swiftJson: String, jsJson: String) throws {
        // Parse both JSON strings
        let swiftData = swiftJson.data(using: .utf8)!
        let jsData = jsJson.data(using: .utf8)!

        let swiftDict = try JSONSerialization.jsonObject(with: swiftData) as! [String: Any]
        let jsDict = try JSONSerialization.jsonObject(with: jsData) as! [String: Any]

        // Extract debug info
        let swiftDebugInfo = swiftDict["debugInfo"] as! [Any]
        let jsDebugInfo = jsDict["debugInfo"] as! [Any]
        for (s, js) in zip(swiftDebugInfo, jsDebugInfo) {
            print("Debug Info")
            print("  - Swift: \(s)")
            print("  - JS: \(js)")
        }

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
            let count = max(swiftDoubles.count, jsDoubles.count)
            var index = 0
            while index < count {
                let swiftDouble = index < swiftDoubles.count ? String(swiftDoubles[index]) : "nil"
                let jsDouble = index < jsDoubles.count ? String(jsDoubles[index]) : "nil"
                print("Index: \(index), Swift: \(swiftDouble), JS: \(jsDouble)")
                index += 1
            }
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
        .enabled(if: ReplayTests.enabled)
    ) func replayErrorInputs() async throws {
        let timezone = ReplayTests.timezone
        let files = try await HttpFiles.listFiles()
        for filePath in files {
            let algorithmComparison = try await HttpFiles.downloadFile(at: filePath)
            print("Checking \(filePath) @ \(algorithmComparison.createdAt)")
            guard timezone == algorithmComparison.timezone else {
                continue
            }
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

            timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

            try await checkFixedJsAgainstSwift(autosensInputs: autosensInputs)
            print("Checked \(filePath) @ \(algorithmComparison.createdAt)")

            timeZoneForTests.resetTimezone()
        }
    }

    @Test("Format autosens inputs for running in JS", .enabled(if: false)) func formatInputs() async throws {
        // this test is meant for one-off analysis so it's ok to hard code
        // a file, just make sure to _not_ check in updates to this to
        // avoid polluting our change logs
        let algorithmComparison = try await HttpFiles.downloadFile(at: "/files/432be489-adfd-4799-b469-8d3794d5188e.0.json")
        let autosensInputs = algorithmComparison.autosensInput!

        let encoder = JSONCoding.encoder
        let output = try encoder.encode(autosensInputs)

        let sharedDir = FileManager.default.temporaryDirectory
        let outputURL = sharedDir.appendingPathComponent("autosens_error_inputs.json")
        try output.write(to: outputURL)

        // Print the path so you can find it
        print("Writing to: \(outputURL.path)")

        timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

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

        if case let .success(swiftJson) = autosensResultSwift, case let .success(jsJson) = autosensResultJavascript {
            try compareDeviations(swiftJson: swiftJson, jsJson: jsJson)
        }

        try await checkFixedJsAgainstSwift(autosensInputs: autosensInputs)

        timeZoneForTests.resetTimezone()
    }
}
