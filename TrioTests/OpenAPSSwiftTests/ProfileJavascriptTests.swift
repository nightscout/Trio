import Foundation
import Testing
@testable import Trio

struct ProfileGeneratorTests {
    // Base test inputs that match the JavaScript test setup
    private func createBaseInputs() -> (
        PumpSettings,
        BGTargets,
        [BasalProfileEntry],
        InsulinSensitivities,
        Preferences,
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

        let preferences = Preferences()

        let carbRatios = CarbRatios(
            units: .grams,
            schedule: [
                CarbRatioEntry(start: "00:00", offset: 0, ratio: 20)
            ]
        )

        let tempTargets: [TempTarget] = []
        let model = "523"
        let trioSettings = TrioSettings()

        return (pumpSettings, bgTargets, basalProfile, isf, preferences, carbRatios, tempTargets, model, trioSettings)
    }

    @Test("Basic profile generation should create profile with correct values") func testBasicProfileGeneration() throws {
        let inputs = createBaseInputs()

        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.0,
            bgTargets: inputs.1,
            basalProfile: inputs.2,
            isf: inputs.3,
            preferences: inputs.4,
            carbRatios: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            trioSettings: inputs.8
        )

        #expect(profile.maxIob == 0)
        #expect(profile.dia == 10)
        #expect(profile.sens == 100)
        #expect(profile.currentBasal == 1)
        #expect(profile.maxBg == 100)
        #expect(profile.minBg == 100)
        #expect(profile.carbRatio == 20)
    }

    @Test("Profile with active temp target should use temp target values") func testProfileWithTempTarget() throws {
        var inputs = createBaseInputs()

        // Create temp target 5 minutes ago that lasts 20 minutes
        let currentTime = Date()
        let creationDate = currentTime.addingTimeInterval(-5 * 60)

        let tempTarget = TempTarget(
            name: "Eating Soon",
            createdAt: creationDate,
            targetTop: 80,
            targetBottom: 80,
            duration: 20,
            enteredBy: "Test",
            reason: "Eating Soon",
            isPreset: nil,
            enabled: nil,
            halfBasalTarget: nil
        )

        inputs.6 = [tempTarget]

        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.0,
            bgTargets: inputs.1,
            basalProfile: inputs.2,
            isf: inputs.3,
            preferences: inputs.4,
            carbRatios: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            trioSettings: inputs.8
        )

        #expect(profile.maxIob == 0)
        #expect(profile.dia == 10)
        #expect(profile.sens == 100)
        #expect(profile.currentBasal == 1)
        #expect(profile.maxBg == 80)
        #expect(profile.minBg == 80)
        #expect(profile.carbRatio == 20)
        #expect(profile.temptargetSet == true)
    }

    @Test("Profile with expired temp target should use default values") func testProfileWithExpiredTempTarget() throws {
        var inputs = createBaseInputs()

        // Create temp target 90 minutes ago
        let currentTime = Date()
        let creationDate = currentTime.addingTimeInterval(-90 * 60)

        let tempTarget = TempTarget(
            name: "Eating Soon",
            createdAt: creationDate,
            targetTop: 80,
            targetBottom: 80,
            duration: 20,
            enteredBy: "Test",
            reason: "Eating Soon",
            isPreset: nil,
            enabled: nil,
            halfBasalTarget: nil
        )

        inputs.6 = [tempTarget]

        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.0,
            bgTargets: inputs.1,
            basalProfile: inputs.2,
            isf: inputs.3,
            preferences: inputs.4,
            carbRatios: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            trioSettings: inputs.8
        )

        #expect(profile.maxIob == 0)
        #expect(profile.dia == 10)
        #expect(profile.sens == 100)
        #expect(profile.currentBasal == 1)
        #expect(profile.maxBg == 100)
        #expect(profile.minBg == 100)
        #expect(profile.carbRatio == 20)
    }

    @Test("Profile with zero duration temp target should use default values") func testProfileWithZeroDurationTempTarget() throws {
        var inputs = createBaseInputs()

        // Create temp target 5 minutes ago with 0 duration
        let currentTime = Date()
        let creationDate = currentTime.addingTimeInterval(-5 * 60)

        let tempTarget = TempTarget(
            name: "Eating Soon",
            createdAt: creationDate,
            targetTop: 80,
            targetBottom: 80,
            duration: 0,
            enteredBy: "Test",
            reason: "Eating Soon",
            isPreset: nil,
            enabled: nil,
            halfBasalTarget: nil
        )

        inputs.6 = [tempTarget]

        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.0,
            bgTargets: inputs.1,
            basalProfile: inputs.2,
            isf: inputs.3,
            preferences: inputs.4,
            carbRatios: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            trioSettings: inputs.8
        )

        #expect(profile.maxIob == 0)
        #expect(profile.dia == 10)
        #expect(profile.sens == 100)
        #expect(profile.currentBasal == 1)
        #expect(profile.maxBg == 100)
        #expect(profile.minBg == 100)
        #expect(profile.carbRatio == 20)
    }

    @Test("Profile generation with invalid DIA should throw error") func testInvalidDIA() throws {
        var inputs = createBaseInputs()
        inputs.0 = PumpSettings(
            insulinActionCurve: 1,
            maxBolus: 10,
            maxBasal: 2
        )

        #expect(throws: ProfileError.invalidDIA(value: 1)) {
            _ = try ProfileGenerator.generate(
                pumpSettings: inputs.0,
                bgTargets: inputs.1,
                basalProfile: inputs.2,
                isf: inputs.3,
                preferences: inputs.4,
                carbRatios: inputs.5,
                tempTargets: inputs.6,
                model: inputs.7,
                trioSettings: inputs.8
            )
        }
    }

    @Test("Profile generation with zero basal rate should throw error") func testCurrentBasalZero() throws {
        var inputs = createBaseInputs()
        inputs.2 = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 0.0)
        ]

        // the reason it throws this error is due to some complex logic
        // in Javascript around the handling of nil and 0 basal rate entries
        #expect(throws: ProfileError.invalidMaxDailyBasal(value: 0)) {
            _ = try ProfileGenerator.generate(
                pumpSettings: inputs.0,
                bgTargets: inputs.1,
                basalProfile: inputs.2,
                isf: inputs.3,
                preferences: inputs.4,
                carbRatios: inputs.5,
                tempTargets: inputs.6,
                model: inputs.7,
                trioSettings: inputs.8
            )
        }
    }

    @Test("Profile should store model string correctly") func testModelString() throws {
        var inputs = createBaseInputs()
        inputs.7 = "\"554\"\n"

        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.0,
            bgTargets: inputs.1,
            basalProfile: inputs.2,
            isf: inputs.3,
            preferences: inputs.4,
            carbRatios: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            trioSettings: inputs.8
        )

        #expect(profile.model == "554")
    }

    @Test("Profile should use temptargetSet key in output json") func testTempTargetSetKey() async throws {
        var inputs = createBaseInputs()
        inputs.7 = "\"554\"\n"
        let now = Date()
        let tempTargets = [
            TempTarget(
                name: nil,
                createdAt: now - 1.hoursToSeconds,
                targetTop: 100,
                targetBottom: 80,
                duration: 120,
                enteredBy: nil,
                reason: nil,
                isPreset: nil,
                enabled: nil,
                halfBasalTarget: nil
            )
        ]

        let openAps = OpenAPS(storage: BaseFileStorage(), tddStorage: MockTDDStorage())
        let jsResult = await openAps.makeProfileJavascript(
            preferences: inputs.4,
            pumpSettings: inputs.0,
            bgTargets: inputs.1,
            basalProfile: inputs.2,
            isf: inputs.3,
            carbRatio: inputs.5,
            tempTargets: tempTargets,
            model: inputs.7,
            autotune: RawJSON.null,
            trioSettings: inputs.8
        )

        let swiftResult = OpenAPSSwift.makeProfile(
            preferences: inputs.4,
            pumpSettings: inputs.0,
            bgTargets: inputs.1,
            basalProfile: inputs.2,
            isf: inputs.3,
            carbRatio: inputs.5,
            tempTargets: tempTargets,
            model: inputs.7,
            trioSettings: inputs.8
        )

        let comparison = JSONCompare.createComparison(
            function: .makeProfile,
            swift: swiftResult,
            swiftDuration: 1.0,
            javascript: jsResult,
            javascriptDuration: 1.0,
            iobInputs: nil,
            mealInputs: nil,
            autosensInputs: nil,
            determineBasalInputs: nil
        )

        if comparison.resultType == .valueDifference {
            print(comparison.differences!.prettyPrintedJSON!)
        }

        #expect(comparison.resultType == .matching)
    }
}
