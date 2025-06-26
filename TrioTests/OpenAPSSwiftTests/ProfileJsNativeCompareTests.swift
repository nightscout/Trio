import Foundation
import Testing
@testable import Trio

@Suite("Profile js vs native comparison") struct ProfileJsNativeCompareTests {
    // Base test inputs that match the JavaScript test setup
    private func createBaseInputs() -> (
        Preferences,
        PumpSettings,
        BGTargets,
        [BasalProfileEntry],
        InsulinSensitivities,
        CarbRatios,
        [TempTarget],
        String,
        TrioSettings
    ) {
        let pumpSettings = PumpSettings(
            insulinActionCurve: 10,
            maxBolus: 10,
            maxBasal: 2
        )

        let bgTargets = BGTargets(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            targets: [
                BGTargetEntry(low: 100, high: 120, start: "00:00", offset: 0)
            ]
        )

        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)
        ]

        let isf = InsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: [
                InsulinSensitivityEntry(sensitivity: 100, offset: 0, start: "00:00")
            ]
        )

        var preferences = Preferences()

        // Modify preferences to make sure that modified properties
        // propogate to Profile
        preferences.smbDeliveryRatio = 0.4

        let carbRatios = CarbRatios(
            units: .grams,
            schedule: [
                CarbRatioEntry(start: "00:00", offset: 0, ratio: 20)
            ]
        )

        let tempTargets: [TempTarget] = []
        let model = "\"250\""
        let trioSettings = TrioSettings()

        return (preferences, pumpSettings, bgTargets, basalProfile, isf, carbRatios, tempTargets, model, trioSettings)
    }

    @Test("should compare Profile for js and native with base inputs") func withBasicInputs() async throws {
        let inputs = createBaseInputs()
        let openAps = OpenAPS(storage: BaseFileStorage(), tddStorage: MockTDDStorage())
        let profileJs = await openAps.makeProfileJavascript(
            preferences: inputs.0,
            pumpSettings: inputs.1,
            bgTargets: inputs.2,
            basalProfile: inputs.3,
            isf: inputs.4,
            carbRatio: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            autotune: RawJSON.null,
            trioSettings: inputs.8
        )

        let profileSwift = OpenAPSSwift.makeProfile(
            preferences: inputs.0,
            pumpSettings: inputs.1,
            bgTargets: inputs.2,
            basalProfile: inputs.3,
            isf: inputs.4,
            carbRatio: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            trioSettings: inputs.8
        )

        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: profileSwift,
            swiftDuration: 0.1,
            javascript: profileJs,
            javascriptDuration: 0.1,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        #expect(comparison.resultType == .matching)
    }
}

@Suite("Algorithm Comparison Creation") struct ComparisonCreationTests {
    // Test fixtures
    let matchingJSON = """
    {
        "value": 42
    }
    """

    let differentJSON = """
    {
        "value": 43
    }
    """

    let invalidJSON = "{ invalid json"

    @Test("should create matching comparison when values are identical") func matchingValues() async throws {
        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: .success(matchingJSON),
            swiftDuration: 0.1,
            javascript: .success(matchingJSON),
            javascriptDuration: 0.2,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        #expect(comparison.resultType == .matching)
        #expect(comparison.differences == nil)
        #expect(comparison.jsDuration == 0.2)
        #expect(comparison.swiftDuration == 0.1)
        #expect(comparison.jsException == nil)
        #expect(comparison.swiftException == nil)
        #expect(comparison.comparisonError == nil)
    }

    @Test("should detect value differences") func valueDifferences() async throws {
        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: .success(differentJSON),
            swiftDuration: 0.1,
            javascript: .success(matchingJSON),
            javascriptDuration: 0.2,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        #expect(comparison.resultType == .valueDifference)
        #expect(comparison.differences != nil)
        #expect(comparison.differences?["value"] != nil)
        #expect(comparison.jsDuration == 0.2)
        #expect(comparison.swiftDuration == 0.1)
        #expect(comparison.jsException == nil)
        #expect(comparison.swiftException == nil)
        #expect(comparison.comparisonError == nil)
    }

    @Test("should handle matching exceptions") func matchingExceptions() async throws {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: .failure(error),
            swiftDuration: 0.1,
            javascript: .failure(error),
            javascriptDuration: 0.2,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        #expect(comparison.resultType == .matchingExceptions)
        #expect(comparison.differences == nil)
        #expect(comparison.jsException != nil)
        #expect(comparison.swiftException != nil)
        #expect(comparison.comparisonError == nil)
    }

    @Test("should handle Swift-only exceptions") func swiftOnlyException() async throws {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: .failure(error),
            swiftDuration: 0.1,
            javascript: .success(matchingJSON),
            javascriptDuration: 0.2,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        #expect(comparison.resultType == .swiftOnlyException)
        #expect(comparison.differences == nil)
        #expect(comparison.jsException == nil)
        #expect(comparison.swiftException != nil)
        #expect(comparison.jsDuration == 0.2)
        #expect(comparison.swiftDuration == nil)
        #expect(comparison.comparisonError == nil)
    }

    @Test("should handle JavaScript-only exceptions") func javascriptOnlyException() async throws {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: .success(matchingJSON),
            swiftDuration: 0.1,
            javascript: .failure(error),
            javascriptDuration: 0.2,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        #expect(comparison.resultType == .jsOnlyException)
        #expect(comparison.differences == nil)
        #expect(comparison.jsException != nil)
        #expect(comparison.swiftException == nil)
        #expect(comparison.jsDuration == nil)
        #expect(comparison.swiftDuration == 0.1)
        #expect(comparison.comparisonError == nil)
    }

    @Test("should handle comparison errors with invalid JSON") func comparisonError() async throws {
        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: .success(invalidJSON),
            swiftDuration: 0.1,
            javascript: .success(matchingJSON),
            javascriptDuration: 0.2,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        #expect(comparison.resultType == .comparisonError)
        #expect(comparison.differences == nil)
        #expect(comparison.jsException == nil)
        #expect(comparison.swiftException == nil)
        #expect(comparison.comparisonError != nil)
        #expect(comparison.jsDuration == 0.2)
        #expect(comparison.swiftDuration == 0.1)
    }
}
