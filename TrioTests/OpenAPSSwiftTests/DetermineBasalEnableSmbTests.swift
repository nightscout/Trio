import Foundation
import Testing
@testable import Trio

@Suite("DosingEngine: shouldEnableSmb Tests") struct DetermineBasalEnableSmbTests {
    /// Helper to create a default set of inputs.
    /// Each test can then modify the specific properties relevant to its case.
    private func createDefaultInputs() -> (
        profile: Profile,
        meal: ComputedCarbs,
        currentGlucose: Decimal,
        adjustedTargetGlucose: Decimal,
        minGuardGlucose: Decimal,
        threshold: Decimal,
        glucoseStatus: GlucoseStatus,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        clock: Date
    ) {
        var profile = Profile()
        // Ensure default is false so we can test enabling conditions.
        profile.enableSMBAlways = false
        profile.temptargetSet = false

        let meal = ComputedCarbs(
            carbs: 0,
            mealCOB: 0,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: Date().timeIntervalSince1970
        )

        let glucoseStatus = GlucoseStatus(
            delta: 0,
            glucose: 120,
            noise: 0,
            shortAvgDelta: 0,
            longAvgDelta: 0,
            date: Date(),
            lastCalIndex: nil,
            device: "test"
        )

        let trioCustomOrefVariables = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 100,
            useOverride: false,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 0,
            uamMinutes: 0
        )

        return (
            profile: profile,
            meal: meal,
            currentGlucose: 120,
            adjustedTargetGlucose: 100,
            minGuardGlucose: 110,
            threshold: 70,
            glucoseStatus: glucoseStatus,
            trioCustomOrefVariables: trioCustomOrefVariables,
            clock: Date()
        )
    }

    // MARK: - Disabling Conditions

    @Test("Should return false by default with no enabling preferences") func defaultIsFalse() throws {
        let inputs = createDefaultInputs()
        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test("Should disable SMB when smbIsOff is true") func disableWhenSmbIsOff() throws {
        var inputs = createDefaultInputs()
        inputs.trioCustomOrefVariables.smbIsOff = true
        inputs.profile.enableSMBAlways = true // Ensure smbIsOff takes precedence

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test("Should disable SMB with high temp target when not allowed") func disableWithHighTempTarget() throws {
        var inputs = createDefaultInputs()
        inputs.profile.allowSMBWithHighTemptarget = false
        inputs.profile.temptargetSet = true
        inputs.adjustedTargetGlucose = 120

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test("Should disable SMB when minGuardGlucose is below threshold") func disableWhenMinGuardBelowThreshold() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true // Enable SMB initially to test the safety override
        inputs.minGuardGlucose = 65
        inputs.threshold = 70

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
        #expect(decision.minGuardGlucose == 65)
    }

    @Test("Should disable SMB when maxDelta is too high") func disableWhenMaxDeltaTooHigh() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true // Enable SMB initially
        inputs.profile.maxDeltaBgThreshold = 0.2
        inputs.currentGlucose = 100
        // Set maxDelta to be > 20% of currentGlucose
        inputs.glucoseStatus = GlucoseStatus(
            delta: 21,
            glucose: 100,
            noise: 0,
            shortAvgDelta: 5,
            longAvgDelta: 5,
            date: Date(),
            lastCalIndex: nil,
            device: "test"
        )

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
        #expect(decision.reason != nil)
    }

    // MARK: - Enabling Conditions

    @Test("Should enable SMB when enableSMBAlways is true") func enableWhenAlwaysOn() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }

    @Test("Should enable SMB with COB") func enableWithCob() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBWithCOB = true
        inputs.meal = ComputedCarbs(
            carbs: 20,
            mealCOB: 10,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: Date().timeIntervalSince1970
        )

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }

    @Test("Should enable SMB after carbs") func enableAfterCarbs() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAfterCarbs = true
        inputs.meal = ComputedCarbs(
            carbs: 20,
            mealCOB: 0,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: Date().timeIntervalSince1970
        )

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }

    @Test("Should enable SMB with low temp target") func enableWithLowTempTarget() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBWithTemptarget = true
        inputs.profile.temptargetSet = true
        inputs.adjustedTargetGlucose = 90

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }

    @Test("Should enable SMB for high BG") func enableWithHighBg() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBHighBg = true
        inputs.profile.enableSMBHighBgTarget = 140
        inputs.currentGlucose = 145

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }

    // MARK: - Scheduled Off Tests

    @Test("Scheduled Off (Normal): should disable SMB inside the window") func scheduledOffNormal_Inside() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true // Ensure schedule is the only reason for failure
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 9 // 9 AM
        inputs.trioCustomOrefVariables.end = 17 // 5 PM
        inputs.clock = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test("Scheduled Off (Normal): should NOT disable SMB outside the window") func scheduledOffNormal_Outside() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 9 // 9 AM
        inputs.trioCustomOrefVariables.end = 17 // 5 PM
        inputs.clock = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }

    @Test(
        "Scheduled Off (Wrapping): should disable SMB inside the window (after midnight)"
    ) func scheduledOffWrapping_InsideAfterMidnight() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 22 // 10 PM
        inputs.trioCustomOrefVariables.end = 6 // 6 AM
        inputs.clock = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test(
        "Scheduled Off (Wrapping): should disable SMB inside the window (before midnight)"
    ) func scheduledOffWrapping_InsideBeforeMidnight() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 22 // 10 PM
        inputs.trioCustomOrefVariables.end = 6 // 6 AM
        inputs.clock = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test("Scheduled Off (Wrapping): should NOT disable SMB outside the window") func scheduledOffWrapping_Outside() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 22 // 10 PM
        inputs.trioCustomOrefVariables.end = 6 // 6 AM
        inputs.clock = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }

    @Test("Scheduled Off (All Day): should disable SMB") func scheduledOffAllDay() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 0
        inputs.trioCustomOrefVariables.end = 0
        inputs.clock = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test("Scheduled Off (Single Hour): should disable SMB inside the window") func scheduledOffSingleHour_Inside() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 11 // 11 AM
        inputs.trioCustomOrefVariables.end = 11 // 11 AM
        inputs.clock = Calendar.current.date(bySettingHour: 11, minute: 30, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == false)
    }

    @Test("Scheduled Off (Single Hour): should NOT disable SMB outside the window") func scheduledOffSingleHour_Outside() throws {
        var inputs = createDefaultInputs()
        inputs.profile.enableSMBAlways = true
        inputs.trioCustomOrefVariables.smbIsScheduledOff = true
        inputs.trioCustomOrefVariables.start = 11 // 11 AM
        inputs.trioCustomOrefVariables.end = 11 // 11 AM
        inputs.clock = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        let decision = try DosingEngine.makeSMBDosingDecision(
            profile: inputs.profile, meal: inputs.meal, currentGlucose: inputs.currentGlucose,
            adjustedTargetGlucose: inputs.adjustedTargetGlucose,
            minGuardGlucose: inputs.minGuardGlucose,
            threshold: inputs.threshold, glucoseStatus: inputs.glucoseStatus,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables, clock: inputs.clock
        )
        #expect(decision.isEnabled == true)
    }
}
