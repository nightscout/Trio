import Foundation
@testable import FreeAPS
import Testing

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
        FreeAPSSettings
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
        let model = "\"250\""
        let freeaps = FreeAPSSettings()

        return (preferences, pumpSettings, bgTargets, basalProfile, isf, carbRatios, tempTargets, model, freeaps)
    }

    @Test("should compare Profile for js and native with base inputs") func withBasicInputs() async throws {
        let inputs = createBaseInputs()
        let openAps = OpenAPS(storage: BaseFileStorage())
        let profileJs = try! await openAps.makeProfileJavascript(
            preferences: inputs.0,
            pumpSettings: inputs.1,
            bgTargets: inputs.2,
            basalProfile: inputs.3,
            isf: inputs.4,
            carbRatio: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            autotune: RawJSON.null,
            freeaps: inputs.8
        )

        let profileNative = OpenAPSSwift.makeProfile(
            preferences: inputs.0,
            pumpSettings: inputs.1,
            bgTargets: inputs.2,
            basalProfile: inputs.3,
            isf: inputs.4,
            carbRatio: inputs.5,
            tempTargets: inputs.6,
            model: inputs.7,
            freeaps: inputs.8
        )

        let differences = try! JSONCompare.differences(function: .makeProfile, native: profileNative, javascript: profileJs)

        if !differences.isEmpty {
            JSONCompare.prettyPrint(differences)
        }
        #expect(differences.isEmpty)
    }
}
