import Foundation
import Testing
@testable import Trio

@Suite("DetermineBasalAggressiveDosingTests") struct DetermineBasalAggressiveDosingTests {
    private func callCalculateInsulinRequired(
        minForecastGlucose: Decimal,
        eventualGlucose: Decimal,
        targetGlucose: Decimal,
        adjustedSensitivity: Decimal,
        maxIob: Decimal,
        currentIob: Decimal
    ) -> (insulinRequired: Decimal, determination: Determination) {
        let determination = Determination(
            id: UUID(),
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: nil,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )

        return DosingEngine.calculateInsulinRequired(
            minForecastGlucose: minForecastGlucose,
            eventualGlucose: eventualGlucose,
            targetGlucose: targetGlucose,
            adjustedSensitivity: adjustedSensitivity,
            maxIob: maxIob,
            currentIob: currentIob,
            determination: determination
        )
    }

    @Test("should calculate insulin required based on minPredBG when it is lower") func testCalculateBasedOnMinForecast() {
        // minPredBG (150) < eventualBG (180)
        // (150 - 100) / 50 = 1.0 U
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 150,
            eventualGlucose: 180,
            targetGlucose: 100,
            adjustedSensitivity: 50,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == 1.0)
        #expect(result.determination.insulinReq == 1.0)
    }

    @Test("should calculate insulin required based on eventualBG when it is lower") func testCalculateBasedOnEventual() {
        // eventualBG (140) < minPredBG (160)
        // (140 - 100) / 40 = 1.0 U
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 160,
            eventualGlucose: 140,
            targetGlucose: 100,
            adjustedSensitivity: 40,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == 1.0)
        #expect(result.determination.insulinReq == 1.0)
    }

    @Test("should cap insulinReq at max_iob - current_iob") func testCapAtMaxIOB() {
        // (200 - 100) / 20 = 5.0 U required
        // max_iob (3) - current_iob (1) = 2.0 U available space
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 200,
            eventualGlucose: 200,
            targetGlucose: 100,
            adjustedSensitivity: 20,
            maxIob: 3,
            currentIob: 1
        )
        #expect(result.insulinRequired == 2.0)
        #expect(result.determination.reason.contains("max_iob 3"))
    }

    @Test("should not cap if insulinReq is within max_iob limits") func testNoCapWithinLimits() {
        // (140 - 100) / 20 = 2.0 U required
        // max_iob (5) - current_iob (1) = 4.0 U available space
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 140,
            eventualGlucose: 140,
            targetGlucose: 100,
            adjustedSensitivity: 20,
            maxIob: 5,
            currentIob: 1
        )
        #expect(result.insulinRequired == 2.0)
        #expect(!result.determination.reason.contains("max_iob"))
    }

    @Test("should handle negative IOB increasing available space") func testNegativeIOBIncreasesSpace() {
        // (200 - 100) / 20 = 5.0 U required
        // max_iob (3) - current_iob (-1) = 4.0 U available space
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 200,
            eventualGlucose: 200,
            targetGlucose: 100,
            adjustedSensitivity: 20,
            maxIob: 3,
            currentIob: -1
        )
        #expect(result.insulinRequired == 4.0)
        #expect(result.determination.reason.contains("max_iob 3"))
    }

    @Test("should handle negative insulinReq correctly") func testNegativeInsulinReq() {
        // (90 - 100) / 50 = -0.2 U
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 90,
            eventualGlucose: 95,
            targetGlucose: 100,
            adjustedSensitivity: 50,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == -0.2)
    }

    @Test("should round calculations to 2 decimal places") func testRounding() {
        // (133 - 100) / 30 = 1.1
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 133,
            eventualGlucose: 133,
            targetGlucose: 100,
            adjustedSensitivity: 30,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == 1.1)
    }

    private func callDetermineSMBDelivery(
        insulinRequired: Decimal,
        microBolusAllowed: Bool = true,
        smbIsEnabled: Bool = true,
        currentGlucose: Decimal = 120,
        threshold: Decimal = 60,
        profile: Profile,
        mealData: ComputedCarbs = ComputedCarbs(
            carbs: 0,
            mealCOB: 0,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: 0
        ),
        iobData: [IobResult],
        trioCustomOrefVariables: TrioCustomOrefVariables? = nil,
        adjustedCarbRatio: Decimal = 10,
        basal: Decimal = 1.0,
        naiveEventualGlucose: Decimal = 120,
        minIOBForecastedGlucose: Decimal = 120
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        let determination = Determination(
            id: UUID(),
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: nil,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )

        var finalTrioCustomOrefVariables: TrioCustomOrefVariables
        if let customOrefVars = trioCustomOrefVariables {
            finalTrioCustomOrefVariables = customOrefVars
        } else {
            finalTrioCustomOrefVariables = TrioCustomOrefVariables(
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
                smbMinutes: 30,
                uamMinutes: 30
            )
        }

        return try DosingEngine.determineSMBDelivery(
            insulinRequired: insulinRequired,
            microBolusAllowed: microBolusAllowed,
            smbIsEnabled: smbIsEnabled,
            currentGlucose: currentGlucose,
            threshold: threshold,
            profile: profile,
            trioCustomOrefVariables: finalTrioCustomOrefVariables,
            mealData: mealData,
            iobData: iobData,
            currentTime: Date(),
            targetGlucose: profile.targetBg ?? 100,
            naiveEventualGlucose: naiveEventualGlucose,
            minIOBForecastedGlucose: minIOBForecastedGlucose,
            adjustedSensitivity: profile.sens ?? 40,
            adjustedCarbRatio: adjustedCarbRatio,
            basal: basal,
            determination: determination
        )
    }

    @Test("should calculate correct microbolus with rounding") func testMicroBolusRounding() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000) // 10 minutes ago

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // insulinReq = 1.55
        // maxBolus = 1.0 * 30/60 = 0.5
        // smb = min(1.55 * 0.5, 0.5) = min(0.775, 0.5) = 0.5
        // 0.5 is already rounded.
        // Let's try a case where maxBolus is higher.

        profile.maxSMBBasalMinutes = 60
        // maxBolus = 1.0 * 60/60 = 1.0
        // smb = min(1.55 * 0.5, 1.0) = 0.775
        // rounded down to 0.1 increment: 0.7

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.55,
            profile: profile,
            iobData: iobData
        )

        #expect(result.determination.units == 0.7)
    }

    @Test("should apply override factor to maxBolus") func testOverrideFactorMaxBolus() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000) // 10 minutes ago

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // Override factor 2.0 (200%)
        // maxBolus = 1.0 * 2.0 * 30/60 = 1.0
        // insulinReq = 3.0
        // smb = min(3.0 * 0.5, 1.0) = min(1.5, 1.0) = 1.0

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 200, // 2.0 * 100
            useOverride: true,
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
            smbMinutes: 30,
            uamMinutes: 30
        )

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 1.0)
    }

    @Test(
        "should override smbMinutes and uamMinutes when useOverride and advancedSettings are true"
    ) func testOverrideSmbUamMinutes() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30 // 0.5U
        profile.maxUAMSMBBasalMinutes = 30 // 0.5U
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)

        // Case 1: Regular SMB (IOB <= mealInsulinReq)
        // insulinReq = 3.0
        // maxBolus should be 1.0 (60 mins override) instead of 0.5 (30 mins profile)
        // smb = min(3.0 * 0.5, 1.0) = 1.0

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 100,
            useOverride: true,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: true,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 60,
            uamMinutes: 60
        )

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 1.0)

        // Case 2: UAM SMB (IOB > mealInsulinReq)
        // mealCOB = 10, CR = 10 => mealInsulinReq = 1.0
        // iob = 1.5
        let mealData = ComputedCarbs(
            carbs: 0,
            mealCOB: 10,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: 0
        )
        let uamIobData = [IobResult(
            iob: 1.5,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        let uamResult = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            mealData: mealData,
            iobData: uamIobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(uamResult.determination.units == 1.0)
    }

    @Test(
        "should not override smbMinutes and uamMinutes when advancedSettings is false"
    ) func testNoOverrideWhenAdvancedSettingsFalse() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30 // 0.5U
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 100,
            useOverride: true,
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
            smbMinutes: 60,
            uamMinutes: 60
        )

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // insulinReq = 3.0
        // maxBolus should be 0.5 (30 mins from profile), ignoring override 60 because advancedSettings is false
        // smb = min(1.5, 0.5) = 0.5

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 0.5)
    }

    @Test("should use overridePercentage from custom vars if provided") func testOverridePercentageFromCustomVars() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30 // 0.5U
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 200, // 200%
            useOverride: true,
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
            smbMinutes: 30,
            uamMinutes: 30
        )

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // maxBolus = 1.0 * 2.0 * 30/60 = 1.0
        // insulinReq = 3.0
        // smb = min(3.0 * 0.5, 1.0) = 1.0

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 1.0)
    }

    @Test("should not bolus if within SMB interval") func testSMBInterval() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.smbInterval = 3
        profile.sens = 40
        profile.targetBg = 100

        // Last bolus 1 minute ago
        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: now,
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // Setup conditions where temp basal is required so it returns true, but NO units
        // worstCase > 0 => low pred
        // (100 - (90+90)/2) / 40 = 0.25
        // duration = 60 * 0.25 / 1 = 15m
        // 15m -> <30m -> sets smbLowTempReq -> returns true

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 90,
            minIOBForecastedGlucose: 90
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.units == nil)
        #expect(result.determination.reason.contains("Waiting"))
    }

    @Test("should return false if SMB conditions not met") func testGuardConditions() throws {
        var profile = Profile()
        profile.currentBasal = 1.0

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // bg (100) < threshold (110)
        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            currentGlucose: 100,
            threshold: 110,
            profile: profile,
            iobData: iobData
        )

        #expect(result.shouldSetTempBasal == false)
    }

    private func callDetermineHighTempBasal(
        insulinRequired: Decimal,
        basal: Decimal,
        profile: Profile,
        currentTemp: TempBasal
    ) throws -> Determination {
        let determination = Determination(
            id: UUID(),
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: nil,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )

        return try DosingEngine.determineHighTempBasal(
            insulinRequired: insulinRequired,
            basal: basal,
            profile: profile,
            currentTemp: currentTemp,
            determination: determination
        )
    }

    @Test("should set high temp if no temp is running") func testSetHighTempNoTemp() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0 // Unused by logic but good for completeness

        // insulinReq = 1.0. basal = 1.0. rate = 1.0 + 2*1.0 = 3.0.
        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 3.0)
        #expect(result.duration == 30)
        #expect(result.reason.contains("no temp, setting 3U/hr"))
    }

    @Test("should cap rate at maxSafeBasal") func testCapAtMaxSafeBasal() throws {
        var profile = Profile()
        profile.maxBasal = 2.0 // Restrict max basal
        profile.maxDailyBasal = 2.0
        profile.currentBasalSafetyMultiplier = 4
        profile.maxDailySafetyMultiplier = 3
        profile.currentBasal = 1.0

        // insulinReq = 1.0. basal = 1.0. rate = 3.0. Max = 2.0.
        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 2.0)
        #expect(result.reason.contains("adj. req. rate: 3"))
        #expect(result.reason.contains("maxSafeBasal: 2"))
    }

    @Test("should reduce temp if current temp delivers >2x required insulin") func testReduceTempIfScheduledTooHigh() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0

        // insulinReq = 0.5. 2x = 1.0 U.
        // basal = 1.0. rate = 1.0 + 1.0 = 2.0.
        // Current temp: rate 4.0, duration 30m.
        // insulinScheduled = 30 * (4.0 - 1.0) / 60 = 1.5 U.

        let result = try callDetermineHighTempBasal(
            insulinRequired: 0.5,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 30, rate: 4.0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 2.0)
        #expect(result.reason.contains("> 2 * insulinReq"))
    }

    @Test("should do nothing if current temp is sufficient") func testDoNothingIfSufficient() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0

        // insulinReq = 1.0. rate = 3.0.
        // Current temp: rate 3.0, duration 30m.

        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 30, rate: 3.0, temp: .absolute, timestamp: Date())
        )

        // Should return determination without setting rate/duration (nil implies unchanged in this context check?)
        // Wait, determineHighTempBasal returns a Determination. If it calls setTempBasal, rate/duration are set.
        // If it falls through, it returns 'determination' (which has nil rate/duration).

        #expect(result.rate == nil)
        #expect(result.duration == nil)
        #expect(result.reason.contains("temp 3 >~ req 3U/hr"))
    }

    @Test("should set new temp if current temp is insufficient") func testSetNewTempIfInsufficient() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0

        // insulinReq = 1.0. rate = 3.0.
        // Current temp: rate 2.0.

        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 30, rate: 2.0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 3.0)
        #expect(result.duration == 30)
        #expect(result.reason.contains("temp 2<3U/hr"))
    }

    @Test("should set 30m zero temp if durationReq is between 30 and 45") func testSet30mZeroTemp() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq ~ 35
        // duration = 60 * worst / basal => 35 = 60 * worst / 1.0 => worst = 0.583
        // worst = (100 - avg)/50 => avg = 70.85

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 70.85,
            minIOBForecastedGlucose: 70.85
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0)
        #expect(result.determination.duration == 30)
    }

    @Test("should set 60m zero temp if durationReq is > 45") func testSet60mZeroTemp() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq ~ 50
        // 50 = 60 * worst / 1.0 => worst = 0.833
        // worst = (100 - avg)/50 => avg = 58.35

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 58.35,
            minIOBForecastedGlucose: 58.35
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0)
        #expect(result.determination.duration == 60)
    }

    @Test("should cap zero temp duration at 60m") func testCapZeroTempAt60m() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq > 75
        // 100 = 60 * worst / 1.0 => worst = 1.66
        // worst = (100 - avg)/50 => avg = 17

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 17,
            minIOBForecastedGlucose: 17
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0)
        #expect(result.determination.duration == 60)
    }

    @Test("should set low temp if durationReq < 30") func testSetLowTemp() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq = 15
        // 15 = 60 * worst / 1.0 => worst = 0.25
        // worst = (100 - avg)/50 => avg = 87.5

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            basal: 1.0,
            naiveEventualGlucose: 87.5,
            minIOBForecastedGlucose: 87.5
        )

        // Rate = basal * 15/30 = 1.0 * 0.5 = 0.5
        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0.5)
        #expect(result.determination.duration == 30)
    }

    @Test("should not set temp if insulinReq > 0 but microBolus < increment") func testNoTempIfMicroBolusTooSmall() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // insulinReq = 0.05 (positive but small)
        // microBolus < 0.1
        // durationReq = 15m (via predictions)

        let result = try callDetermineSMBDelivery(
            insulinRequired: 0.05,
            profile: profile,
            iobData: iobData,
            basal: 1.0,
            naiveEventualGlucose: 87.5,
            minIOBForecastedGlucose: 87.5
        )

        #expect(result.shouldSetTempBasal == false)
    }

    @Test("should not set temp if durationReq <= 0") func testNoTempIfDurationReqNegative() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // High predictions => negative worstCase => negative durationReq
        // avg = 150 > target 100

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            basal: 1.0,
            naiveEventualGlucose: 150,
            minIOBForecastedGlucose: 150
        )

        #expect(result.shouldSetTempBasal == false)
    }
}
