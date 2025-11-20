import Foundation
import Testing
@testable import Trio

/// The corresponding Javascript tests to confirm these numbers are here:
///  - https://github.com/kingst/trio-oref/blob/dev-fixes-for-swift-comparison/tests/dynamic-isf.test.js
@Suite("DynamicISF Calculation Tests") struct DynamicISFTests {
    // Helper to create common dependencies for tests
    private func createDependencies(
        useNewFormula: Bool = true,
        tdd: Decimal = 30,
        avgTDD: Decimal = 30,
        sensitivity: Decimal = 50,
        minAutosens: Decimal = 0.7,
        maxAutosens: Decimal = 1.2,
        useCustomPeakTime: Bool = false,
        insulinCurve: InsulinCurve = .rapidActing
    ) -> (Profile, Preferences, Decimal, TrioCustomOrefVariables) {
        var preferences = Preferences()
        preferences.useNewFormula = useNewFormula
        preferences.sigmoid = false
        preferences.adjustmentFactor = 0.8
        preferences.adjustmentFactorSigmoid = 0.5
        preferences.useCustomPeakTime = useCustomPeakTime
        preferences.curve = insulinCurve

        var profile = Profile()
        profile.sens = sensitivity
        profile.autosensMin = minAutosens
        profile.autosensMax = maxAutosens
        profile.minBg = 100
        profile.curve = insulinCurve
        profile.useCustomPeakTime = useCustomPeakTime
        profile.insulinPeakTime = 60 // For custom peak time test

        let glucose = Decimal(120)

        let trioVars = TrioCustomOrefVariables(
            average_total_data: avgTDD,
            weightedAverage: tdd,
            currentTDD: tdd,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 100,
            useOverride: false,
            duration: 0,
            unlimited: true,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: true,
            cr: true,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        return (profile, preferences, glucose, trioVars)
    }

    @Test("Returns nil if dISF is disabled") func disabledReturnsNil() throws {
        let (profile, preferences, glucose, trioVars) = createDependencies(useNewFormula: false)

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )

        #expect(result == nil)
    }

    @Test("Returns nil for invalid autosens limits") func invalidLimitsReturnsNil() throws {
        let (profile, preferences, glucose, trioVars) = createDependencies(minAutosens: 1.2, maxAutosens: 1.2)

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )
        #expect(result == nil)
    }

    @Test("Logarithmic formula calculates all result fields correctly") func logarithmicFormula() throws {
        let (profile, preferences, glucose, trioVars) = createDependencies()

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )!

        #expect(result.insulinFactor == 55)
        #expect(result.tddRatio.rounded(toPlaces: 2) == 1)
        #expect(result.ratio.rounded(toPlaces: 2) == 0.77)
    }

    @Test("Sigmoid formula calculates all result fields correctly") func sigmoidFormula() throws {
        var (profile, preferences, glucose, trioVars) = createDependencies()
        preferences.sigmoid = true

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )!

        #expect(result.insulinFactor == 55)
        #expect(result.tddRatio == 1.0)
        #expect(result.ratio.rounded(scale: 2) == Decimal(string: "1.06"))
    }

    @Test("Uses default TDD ratio when average TDD is zero") func defaultTddRatio() throws {
        let (profile, preferences, glucose, trioVars) = createDependencies(avgTDD: 0)

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )!

        #expect(result.tddRatio == 1.0)
        #expect(result.ratio.rounded(toPlaces: 2) == 0.77)
    }

    @Test("Uses custom peak time when enabled") func customPeakTime() throws {
        let (profile, preferences, glucose, trioVars) = createDependencies(useCustomPeakTime: true)

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )!

        // 120 - profile.insulinPeakTime (60) = 60
        #expect(result.insulinFactor == 60)
    }

    @Test("Uses ultra-rapid insulin factor correctly") func ultraRapidInsulin() throws {
        let (profile, preferences, glucose, trioVars) = createDependencies(insulinCurve: .ultraRapid)

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )!

        #expect(result.ratio.rounded(scale: 2) == Decimal(string: "0.7"))
    }

    @Test("Sigmoid handles maxLimit of 1 correctly") func sigmoidMaxLimitOne() throws {
        var (profile, preferences, glucose, trioVars) = createDependencies(maxAutosens: 1.0)
        preferences.sigmoid = true

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )!

        #expect(result.insulinFactor == 55)
        #expect(result.tddRatio == 1.0)
        // BUG: you would expect this to be 1 but because of the fudge factor the
        // JS code uses to avoid divide by 0 it 0.99
        #expect(result.ratio.rounded(scale: 2) == Decimal(string: "0.99"))
    }

    @Test("Override with sigmoid adjusts target and ratio correctly") func overrideWithSigmoid() throws {
        var (profile, preferences, glucose, trioVars) = createDependencies()
        preferences.sigmoid = true
        trioVars.useOverride = true
        trioVars.overrideTarget = 80
        trioVars.overridePercentage = 80

        let result = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: glucose,
            trioCustomOrefVariables: trioVars
        )!

        #expect(result.ratio.rounded(toPlaces: 2) == Decimal(string: "1.11"))
    }
}
