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
            clock: autosensInputs.clock,
            prepareFile: OpenAPSFixed.prepare
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

        // Extract deviationsUnsorted arrays
        let swiftDeviations = swiftDict["deviationsUnsorted"] as! [Any]
        let jsDeviations = jsDict["deviationsUnsorted"] as! [Any]

        let combined: [String: Any] = [
            "swiftDebugInfo": swiftDebugInfo,
            "jsDebugInfo": jsDebugInfo,
            "swiftDeviations": swiftDeviations,
            "jsDeviations": jsDeviations
        ]
        let sharedDir = FileManager.default.temporaryDirectory
        let outputURL = sharedDir.appendingPathComponent("autosens_debug.json")
        let jsonData = try JSONSerialization.data(withJSONObject: combined, options: .prettyPrinted)
        try jsonData.write(to: outputURL)
        print("Writing debug info to: \(outputURL.path)")

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

            if IobJsonTests.pumpIsSuspended(history: autosensInputs.history) {
                print("Skipping, known issue with JS and currently suspended pumps")
                continue
            }

            timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

            try await checkFixedJsAgainstSwift(autosensInputs: autosensInputs)
            print("Checked \(filePath) @ \(algorithmComparison.createdAt)")

            timeZoneForTests.resetTimezone()
        }
    }

    @Test("Compare IoB calculation at specific time", .enabled(if: false)) func compareIobAtTime() async throws {
        // Hard-code the file and time to investigate
        let filePath = "/files/9e146319-5160-482e-9135-f461b97f1a9f.0.json"
        let targetClock = Date("2025-09-08T10:42:44.333Z")!

        let algorithmComparison = try await HttpFiles.downloadFile(at: filePath)
        guard let autosensInputs = algorithmComparison.autosensInput else {
            print("No autosensInputs found")
            return
        }

        timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

        let profile = autosensInputs.profile

        // Prepare treatments the same way AutosensGenerator does
        let swiftTreatments = try IobHistory.calcTempTreatments(
            history: autosensInputs.history.map { $0.computedEvent() },
            profile: profile,
            clock: autosensInputs.clock,
            autosens: nil,
            zeroTempDuration: nil
        )

        let encoder = JSONCoding.encoder
        var output = try encoder.encode(swiftTreatments)

        let sharedDir = FileManager.default.temporaryDirectory
        var outputURL = sharedDir.appendingPathComponent("swift_treatments.json")
        try output.write(to: outputURL)

        print("Writing \(outputURL.path)")

        // Set up profile with currentBasal for this time (both Swift and JS autosens do this)
        var simulationProfile = profile
        simulationProfile.currentBasal = try Basal.basalLookup(autosensInputs.basalProfile, now: targetClock)
        simulationProfile.temptargetSet = false

        // Calculate Swift IoB at this time
        let swiftIob = try IobCalculation.iobTotal(
            treatments: swiftTreatments,
            profile: simulationProfile,
            time: targetClock
        )

        let openAps = OpenAPSFixed()
        let jsTreatmentsRaw = try await openAps.iobHistory(
            pumphistory: autosensInputs.history,
            profile: try JSONBridge.to(autosensInputs.profile),
            clock: autosensInputs.clock,
            autosens: RawJSON.null,
            zeroTempDuration: RawJSON.null
        )

        let jsTreatments = try JSONDecoder()
            .decode([IobJsonTests.IobHistoryResult].self, from: jsTreatmentsRaw.rawJSON.data(using: .utf8)!)

        output = try encoder.encode(jsTreatments)
        outputURL = sharedDir.appendingPathComponent("js_treatments.json")
        try output.write(to: outputURL)

        print("Writing \(outputURL.path)")

        print("Swift IoB at \(targetClock):")
        print("  iob: \(swiftIob.iob)")
        print("  activity: \(swiftIob.activity)")

        timeZoneForTests.resetTimezone()
    }

    @Test("Format autosens inputs for running in JS", .enabled(if: false)) func formatInputs() async throws {
        // this test is meant for one-off analysis so it's ok to hard code
        // a file, just make sure to _not_ check in updates to this to
        // avoid polluting our change logs
        let algorithmComparison = try await HttpFiles.downloadFile(at: "/files/2084152d-a95e-4d0e-9254-e0951f7aa519.0.json")
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
            clock: autosensInputs.clock,
            prepareFile: OpenAPSFixed.prepare
        )

        if case let .success(swiftJson) = autosensResultSwift, case let .success(jsJson) = autosensResultJavascript {
            try compareDeviations(swiftJson: swiftJson, jsJson: jsJson)
        }

        try await checkFixedJsAgainstSwift(autosensInputs: autosensInputs)

        timeZoneForTests.resetTimezone()
    }

    @Test(
        "Format autosens inputs for running in JS, 24 hours only",
        .enabled(if: false)
    ) func formatInputsFixedTime() async throws {
        // this test is meant for one-off analysis so it's ok to hard code
        // a file, just make sure to _not_ check in updates to this to
        // avoid polluting our change logs
        let algorithmComparison = try await HttpFiles.downloadFile(at: "/files/2084152d-a95e-4d0e-9254-e0951f7aa519.0.json")
        let autosensInputs = algorithmComparison.autosensInput!

        // change these variables to switch between 24 and 8 hours
        // 288 for 24 hours, 96 for 8 hours
        let maxDeviations = 288
        // OpenAPSFixed.prepare24 and OpenAPSFixed.prepare8
        let prepareFile = OpenAPSFixed.prepare24

        let encoder = JSONCoding.encoder
        let output = try encoder.encode(autosensInputs)

        let sharedDir = FileManager.default.temporaryDirectory
        let outputURL = sharedDir.appendingPathComponent("autosens_error_inputs.json")
        try output.write(to: outputURL)

        // Print the path so you can find it
        print("Writing to: \(outputURL.path)")

        timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

        let openAps = OpenAPSFixed()

        let glucose = try JSONBridge.glucose(from: autosensInputs.glucose)
        let pumpHistory = try JSONBridge.pumpHistory(from: autosensInputs.history)
        let basalProfile = try JSONBridge.basalProfile(from: autosensInputs.basalProfile)
        let profile = autosensInputs.profile
        let carbs = try JSONBridge.carbs(from: autosensInputs.carbs)
        let tempTargets = try JSONBridge.tempTargets(from: autosensInputs.tempTargets)
        let clock = autosensInputs.clock

        let autosensResultSwift = try AutosensGenerator.generate(
            glucose: glucose,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: profile,
            carbs: carbs,
            tempTargets: tempTargets,
            maxDeviations: maxDeviations,
            clock: clock,
            includeDeviationsForTesting: true
        )

        let autosensResultJavascript = await openAps.autosenseJavascript(
            glucose: autosensInputs.glucose,
            pumpHistory: autosensInputs.history,
            basalprofile: autosensInputs.basalProfile,
            profile: try JSONBridge.to(autosensInputs.profile),
            carbs: autosensInputs.carbs,
            temptargets: autosensInputs.tempTargets,
            clock: autosensInputs.clock,
            prepareFile: prepareFile
        )

        if case let .success(jsJson) = autosensResultJavascript {
            try compareDeviations(swiftJson: JSONBridge.to(autosensResultSwift), jsJson: jsJson)
        }

        try await checkFixedJsAgainstSwift(autosensInputs: autosensInputs)

        timeZoneForTests.resetTimezone()
    }
}
