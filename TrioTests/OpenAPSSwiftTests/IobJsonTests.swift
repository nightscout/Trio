import Foundation
import Testing
@testable import Trio

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
    let timeZoneForTests = TimeZoneForTests()

    struct IobHistoryResult: Codable {
        var insulin: Decimal?
        var rate: Decimal?
        var duration: Decimal?
        var timestamp: String?
        var started_at: String?
        var created_at: String?
        var date: Decimal?

        enum CodingKeys: String, CodingKey {
            case insulin
            case rate
            case duration
            case timestamp
            case started_at
            case created_at
            case date
        }
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

            timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

            try await checkFixedJsAgainstSwift(iobInputs: iobInputs)
            try await checkBundleJsAgainstSwift(iobInputs: iobInputs)

            timeZoneForTests.resetTimezone()
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
            iobInputs: nil,
            mealInputs: nil
        )

        if comparison.resultType != .valueDifference {
            print("REPLAY ERROR: bundle JS did't produce value difference")
        }

        #expect(comparison.resultType == .valueDifference)
    }

    func checkHistoryConsistency(swiftTreatments: [ComputedPumpHistoryEvent], jsTreatments: [IobHistoryResult]) {
        let swiftNetBolus = swiftTreatments.compactMap(\.insulin).filter({ $0 >= 0.1 }).reduce(0, +)
        let jsNetBolus = jsTreatments.compactMap(\.insulin).filter({ $0 >= 0.1 }).reduce(0, +)

        let swiftNetBasal = swiftTreatments.compactMap(\.insulin).filter({ $0 < 0.1 }).reduce(0, +)
        let jsNetBasal = jsTreatments.compactMap(\.insulin).filter({ $0 < 0.1 }).reduce(0, +)

        #expect(swiftNetBasal == jsNetBasal)
        #expect(swiftNetBolus == jsNetBolus)
    }

    func checkRunningBasal(swiftTreatments: [ComputedPumpHistoryEvent], jsTreatments: [IobHistoryResult]) {
        let swiftBasals = swiftTreatments.filter({ $0.rate != nil }).filter({ $0.duration! > 0 })
        let jsBasals = jsTreatments.filter({ $0.rate != nil }).filter({ $0.duration! > 0 })

        #expect(swiftBasals.count == jsBasals.count)
        for (swift, js) in zip(swiftBasals, jsBasals) {
            #expect(Decimal(swift.date) == js.date!)
            #expect(swift.duration!.isWithin(0.01, of: js.duration!))
            #expect(swift.rate == js.rate)

            let start = js.date!
            let end = js.date! + js.duration! * 60 * 1000
            let swiftTempBolus = swiftTreatments
                .filter({ Decimal($0.date) >= start && Decimal($0.date) < end && $0.insulin != nil && $0.insulin! < 0.1 })
                .map({ $0.insulin! }).reduce(0, +)
            let jsTempBolus = jsTreatments
                .filter({ $0.date! >= start && $0.date! < end && $0.insulin != nil && $0.insulin! < 0.1 }).map({ $0.insulin! })
                .reduce(0, +)

            if swiftTempBolus != jsTempBolus {
                print("temp bolus @ \(swift.timestamp) mismatch swift: \(swiftTempBolus) js: \(jsTempBolus)")
            }
            #expect(swiftTempBolus == jsTempBolus)
        }
    }

    @Test("Debug utility for checking iob-history", .enabled(if: false)) func debugIobHistory() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: "iob-error-log", ofType: "json")!
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let algorithmComparison = try decoder.decode(AlgorithmComparison.self, from: data)
        let iobInputs = algorithmComparison.iobInput!

        timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

        let swiftIobHistory = try IobHistory.calcTempTreatments(
            history: iobInputs.history.map { $0.computedEvent() },
            profile: iobInputs.profile,
            clock: iobInputs.clock,
            autosens: iobInputs.autosens,
            zeroTempDuration: nil
        )

        let openAps = OpenAPSFixed()
        let jsIobHistoryRaw = try await openAps.iobHistory(
            pumphistory: iobInputs.history,
            profile: JSONBridge.to(iobInputs.profile),
            clock: iobInputs.clock,
            autosens: JSONBridge.to(iobInputs.autosens),
            zeroTempDuration: RawJSON.null
        )
        let jsIobHistory = try JSONDecoder().decode([IobHistoryResult].self, from: jsIobHistoryRaw.rawJSON.data(using: .utf8)!)

        let encoder = JSONCoding.encoder
        var output = try encoder.encode(swiftIobHistory)
        var sharedDir = FileManager.default.temporaryDirectory
        var outputURL = sharedDir.appendingPathComponent("swift_treatments.json")
        print("Writing to: \(outputURL.path)")
        try output.write(to: outputURL)

        output = try encoder.encode(jsIobHistory)
        sharedDir = FileManager.default.temporaryDirectory
        outputURL = sharedDir.appendingPathComponent("js_treatments.json")
        print("Writing to: \(outputURL.path)")
        try output.write(to: outputURL)

        checkHistoryConsistency(swiftTreatments: swiftIobHistory, jsTreatments: jsIobHistory)
        checkRunningBasal(swiftTreatments: swiftIobHistory, jsTreatments: jsIobHistory)

        timeZoneForTests.resetTimezone()
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

        timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)

        let treatments = try IobHistory.calcTempTreatments(
            history: iobInputs.history.map { $0.computedEvent() },
            profile: iobInputs.profile,
            clock: iobInputs.clock,
            autosens: iobInputs.autosens,
            zeroTempDuration: nil
        )

        let iobSomething = try IobCalculation.iobTotal(treatments: treatments, profile: iobInputs.profile, time: iobInputs.clock)

        timeZoneForTests.resetTimezone()

        print(iobSomething.prettyPrintedJSON!)

        let treatmentsOut = try encoder.encode(treatments)
        let treatmentsUrl = sharedDir.appendingPathComponent("treatments.json")

        print("Writing to: \(treatmentsUrl.path)")

        try treatmentsOut.write(to: treatmentsUrl)
    }
}
