import Foundation
import Testing
@testable import Trio

@Suite("Profile testing using JSON inputs", .serialized) struct ProfileJsonTests {
    let timeZoneForTests = TimeZoneForTests()

    @Test(
        "Profile should produce same results for fixed JS",
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
            guard let profileInputs = algorithmComparison.makeProfileInput else {
                print("Skipping, no profileInputs found")
                if let str = algorithmComparison.comparisonError {
                    print(str)
                }
                if let str = algorithmComparison.swiftException {
                    print(str)
                }
                continue
            }

            timeZoneForTests.setTimezone(identifier: algorithmComparison.timezone)
            try await checkFixedJsAgainstSwift(profileInputs: profileInputs)
            print("Checked \(filePath) \(algorithmComparison.timezone)")
            timeZoneForTests.resetTimezone()
        }
    }

    func checkFixedJsAgainstSwift(profileInputs: MakeProfileInputs) async throws {
        let openAps = OpenAPSFixed()
        let profileResultSwift = OpenAPSSwift.makeProfile(
            preferences: profileInputs.preferences,
            pumpSettings: profileInputs.pumpSettings,
            bgTargets: profileInputs.bgTargets,
            basalProfile: profileInputs.basalProfile,
            isf: profileInputs.isf,
            carbRatio: profileInputs.carbRatios,
            tempTargets: profileInputs.tempTargets,
            model: profileInputs.model,
            trioSettings: profileInputs.trioSettings,
            clock: profileInputs.clock
        )

        let profileResultJavascript = await openAps.makeProfileJavascript(
            preferences: profileInputs.preferences,
            pumpSettings: profileInputs.pumpSettings,
            bgTargets: profileInputs.bgTargets,
            basalProfile: profileInputs.basalProfile,
            isf: profileInputs.isf,
            carbRatio: profileInputs.carbRatios,
            tempTargets: profileInputs.tempTargets,
            model: profileInputs.model,
            autotune: RawJSON.null,
            trioSettings: profileInputs.trioSettings,
            clock: profileInputs.clock
        )

        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: profileResultSwift,
            swiftDuration: 0.1,
            javascript: profileResultJavascript,
            javascriptDuration: 0.1,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil,
            makeProfileInputs: nil
        )

        if comparison.resultType == .valueDifference {
            print(comparison.differences!.prettyPrintedJSON!)
        }

        if comparison.resultType != .matching {
            print("REPLAY ERROR: Fixed JS didn't match")
        }

        #expect(comparison.resultType == .matching)
    }
}
