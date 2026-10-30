import Foundation
import Testing
@testable import Trio

/// The loop's shared oref phases against the steps `OpenAPS.createProfiles` and `OpenAPS.determineBasal` ran
/// inline before they were shared, on every parity scenario.
@Suite("OrefPipeline phases") struct OrefPipelineTests {
    @Test(
        "profile and dose give what the phone's inline steps gave",
        arguments: ParityScenarios.allNames, [true, false]
    ) func phasesMatchInlineSteps(scenarioName: String, hasSufficientTDD: Bool) throws {
        let scenario = ParityScenarios.build(scenarioName)
        let supportedBasalRates = ParityInputs.supportedBasalRates()
        let activeTempTarget = scenario.tempTargets.last.flatMap { tempTarget in
            tempTarget.targetBottom.map { (target: $0, halfBasalTarget: tempTarget.halfBasalTarget) }
        }

        // createProfiles, inline
        var profilePreferences = scenario.preferences
        if let activeTempTarget,
           let effectiveHBT = TempTargetCalculations.computeEffectiveHBT(
               tempTargetHalfBasalTarget: activeTempTarget.halfBasalTarget,
               settingHalfBasalTarget: scenario.preferences.halfBasalExerciseTarget,
               target: activeTempTarget.target,
               autosensMax: scenario.preferences.autosensMax
           ),
           effectiveHBT != scenario.preferences.halfBasalExerciseTarget
        {
            profilePreferences.halfBasalExerciseTarget = effectiveHBT
        }
        if scenario.preferences.lowTemptargetLowersSensitivity, scenario.preferences.autosensMax <= 1 {
            profilePreferences.lowTemptargetLowersSensitivity = false
        }
        let inlineProfile = try ProfileGenerator.generate(
            pumpSettings: scenario.pumpSettings,
            bgTargets: scenario.bgTargets,
            basalProfile: scenario.basalProfile,
            isf: scenario.isf,
            preferences: profilePreferences.clamped(for: .closed),
            carbRatios: scenario.carbRatios,
            tempTargets: scenario.tempTargets,
            clock: scenario.clock
        )

        let autosens = try OrefPipeline.autosens(
            glucose: scenario.glucose,
            pumpHistory: scenario.pumpHistory,
            basalProfile: scenario.basalProfile,
            profile: inlineProfile,
            carbs: scenario.carbs,
            tempTargets: scenario.tempTargets,
            clock: scenario.clock
        )

        // determineBasal, inline
        var dosingProfile = inlineProfile
        dosingProfile.supportedBasalRates = supportedBasalRates
        dosingProfile.suspendOnly = false
        let meal = try MealGenerator.generate(
            pumpHistory: scenario.pumpHistory,
            profile: dosingProfile,
            basalProfile: scenario.basalProfile,
            clock: scenario.clock,
            carbHistory: scenario.carbs,
            glucoseHistory: scenario.glucose
        )
        let inlineIOB = try IobGenerator.generate(
            history: scenario.pumpHistory.removingDuplicateSuspendResumeEvents(),
            profile: dosingProfile,
            clock: scenario.clock,
            autosens: autosens
        )
        var preferences = scenario.preferences.clamped(for: .closed)
        if !hasSufficientTDD, preferences.useNewFormula {
            preferences.useNewFormula = false
            preferences.sigmoid = false
        }
        let inlineDetermination = Result<Determination?, Error> {
            guard let meal else { throw DeterminationError.missingInputs }
            guard var determination = try DeterminationGenerator.generate(
                profile: dosingProfile,
                preferences: preferences,
                currentTemp: scenario.currentTemp,
                iobData: inlineIOB,
                mealData: meal,
                autosensData: autosens,
                reservoirData: scenario.reservoir,
                glucose: scenario.glucose,
                microBolusAllowed: true,
                trioCustomOrefVariables: scenario.orefVariables,
                currentTime: scenario.clock
            ), let deliverAt = determination.deliverAt else { return nil }
            determination.timestamp = deliverAt
            return determination
        }

        // the shared phases
        let profile = try OrefPipeline.profile(
            pumpSettings: scenario.pumpSettings,
            bgTargets: scenario.bgTargets,
            basalProfile: scenario.basalProfile,
            isf: scenario.isf,
            carbRatios: scenario.carbRatios,
            tempTargets: scenario.tempTargets,
            preferences: scenario.preferences,
            activeTempTarget: activeTempTarget,
            dosingMode: .closed,
            clock: scenario.clock
        )
        let dosing = try OrefPipeline.dose(
            profile: profile,
            basalProfile: scenario.basalProfile,
            autosens: autosens,
            glucose: scenario.glucose,
            pumpHistory: scenario.pumpHistory,
            carbs: scenario.carbs,
            currentTemp: scenario.currentTemp,
            reservoir: scenario.reservoir,
            preferences: scenario.preferences,
            dosingMode: .closed,
            hasSufficientTDD: hasSufficientTDD,
            supportedBasalRates: supportedBasalRates,
            trioCustomOrefVariables: scenario.orefVariables,
            clock: scenario.clock,
            currentTime: scenario.clock
        )

        #expect(try ParityHarness.canonicalJSON(profile) == ParityHarness.canonicalJSON(inlineProfile))
        #expect(try ParityHarness.canonicalJSON(dosing.iob) == ParityHarness.canonicalJSON(inlineIOB))
        switch (dosing.determination, inlineDetermination) {
        case let (.success(shared), .success(inline)):
            #expect(
                try ParityHarness.normalizeDeterminationId(ParityHarness.canonicalJSON(shared)) ==
                    ParityHarness.normalizeDeterminationId(ParityHarness.canonicalJSON(inline))
            )
        case (.failure, .failure):
            break
        default:
            Issue.record("one path determined and the other failed")
        }
    }
}
