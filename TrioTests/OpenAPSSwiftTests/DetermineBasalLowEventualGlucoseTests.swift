import Foundation
import Testing
@testable import Trio

@Suite("DetermineBasal low eventual glucose") struct DetermineBasalLowEventualGlucoseTests {
    // Helper to create a mock IOB array with linear decay for testing purposes
    private func mockIobArray(iob: Decimal, activity: Decimal, currentTime: Date) -> [IobResult] {
        (0 ..< 48).map { i in
            IobResult(
                iob: iob - (activity * Decimal(i)),
                activity: activity,
                basaliob: 0,
                bolusiob: 0,
                netbasalinsulin: 0,
                bolusinsulin: 0,
                time: currentTime,
                iobWithZeroTemp: IobResult.IobWithZeroTemp(
                    iob: 0, activity: 0, basaliob: 0, bolusiob: 0, netbasalinsulin: 0, bolusinsulin: 0, time: currentTime
                ),
                lastBolusTime: nil,
                lastTemp: IobResult.LastTemp(
                    rate: 0,
                    timestamp: currentTime,
                    started_at: currentTime,
                    date: UInt64(currentTime.timeIntervalSince1970 * 1000),
                    duration: 0
                )
            )
        }
    }

    private func createDefaultInputs(currentTime: Date = Date()) -> (
        profile: Profile,
        preferences: Preferences,
        currentTemp: TempBasal,
        iobData: [IobResult],
        mealData: ComputedCarbs,
        autosensData: Autosens,
        reservoirData: Decimal,
        glucoseStatus: GlucoseStatus,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        currentTime: Date
    ) {
        var profile = Profile()
        profile.maxIob = 2.5
        profile.dia = 3
        profile.currentBasal = 1.0
        profile.maxDailyBasal = 1.3
        profile.maxBasal = 3.5
        profile.maxBg = 120
        profile.minBg = 100
        profile.sens = 50
        profile.carbRatio = 10
        profile.thresholdSetting = 80
        profile.temptargetSet = false
        profile.bolusIncrement = 0.1
        profile.useCustomPeakTime = false
        profile.curve = .rapidActing
        profile.enableUAM = false // Important for these tests

        var preferences = Preferences()
        preferences.useNewFormula = false
        preferences.sigmoid = false
        preferences.adjustmentFactor = 0.8
        preferences.adjustmentFactorSigmoid = 0.5
        preferences.curve = .rapidActing
        preferences.useCustomPeakTime = false

        let currentTemp = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: currentTime)
        let iobData = mockIobArray(iob: 0, activity: 0, currentTime: currentTime)
        let mealData = ComputedCarbs(
            carbs: 0,
            mealCOB: 0,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [0, 0, 0, 0, 0],
            lastCarbTime: 0
        )
        let autosensData = Autosens(ratio: 1.0, newisf: nil)
        let glucoseStatus = GlucoseStatus(
            delta: 0,
            glucose: 115,
            noise: 1,
            shortAvgDelta: 0,
            longAvgDelta: 0.1,
            date: currentTime,
            lastCalIndex: nil,
            device: "test"
        )

        let trioCustomOrefVariables = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: currentTime,
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
            uamMinutes: 30,
            shouldProtectDueToHIGH: false
        )

        return (
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: 100,
            glucoseStatus: glucoseStatus,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )
    }

    @Test("should set a low temp when eventual BG is low and rising") func lowTempRising() throws {
        var (
            profile, preferences, currentTemp, _, mealData, autosensData, reservoirData, _, trioCustomOrefVariables, currentTime
        ) = createDefaultInputs()

        profile.minBg = 100
        let glucoseStatus = GlucoseStatus(
            delta: 1, glucose: 90, noise: 1, shortAvgDelta: 1, longAvgDelta: 0.1, date: currentTime, lastCalIndex: nil,
            device: "test"
        )
        let iobData = mockIobArray(iob: 0, activity: 0, currentTime: currentTime)

        let result = try DeterminationGenerator.determineBasal(
            profile: profile, preferences: preferences, currentTemp: currentTemp, iobData: iobData, mealData: mealData,
            autosensData: autosensData, reservoirData: reservoirData, glucoseStatus: glucoseStatus,
            trioCustomOrefVariables: trioCustomOrefVariables, currentTime: currentTime
        )

        #expect(result?.rate == 0.7)
        #expect(result?.duration == 30)
        #expect(result?.reason.contains("setting 0.7U/hr") == true)
    }
}

@Suite("DosingEngine.handleLowEventualGlucose") struct HandleLowEventualGlucoseTests {
    private func defaultProfile() -> Profile {
        var profile = Profile()
        profile.minBg = 100
        profile.targetBg = 100
        profile.currentBasal = 1.0
        profile.maxDailyBasal = 1.3
        profile.maxBasal = 3.5
        profile.sens = 50
        return profile
    }

    private func callHandleLowEventualGlucose(
        eventualGlucose: Decimal = 90,
        minGlucose: Decimal? = nil,
        targetGlucose: Decimal? = nil,
        minDelta: Decimal = 0,
        expectedDelta: Decimal = 0,
        carbsRequired: Decimal = 0,
        naiveEventualGlucose: Decimal = 90,
        glucoseStatus: GlucoseStatus = GlucoseStatus(
            delta: 0,
            glucose: 100,
            noise: 1,
            shortAvgDelta: 0,
            longAvgDelta: 0,
            date: Date(),
            lastCalIndex: nil,
            device: "test"
        ),
        currentTemp: TempBasal = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date()),
        basal: Decimal? = nil,
        profile: Profile? = nil,
        determination: Determination? = nil,
        adjustedSensitivity: Decimal? = nil,
        overrideFactor: Decimal = 1
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        let testProfile = profile ?? defaultProfile()
        let testDetermination = determination ?? Determination(
            id: nil,
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
            manualBolusErrorString: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )

        return try DosingEngine.handleLowEventualGlucose(
            eventualGlucose: eventualGlucose,
            minGlucose: minGlucose ?? testProfile.minBg!,
            targetGlucose: targetGlucose ?? testProfile.targetBg!,
            minDelta: minDelta,
            expectedDelta: expectedDelta,
            carbsRequired: carbsRequired,
            naiveEventualGlucose: naiveEventualGlucose,
            glucoseStatus: glucoseStatus,
            currentTemp: currentTemp,
            basal: basal ?? testProfile.currentBasal!,
            profile: testProfile,
            determination: testDetermination,
            adjustedSensitivity: adjustedSensitivity ?? testProfile.sens!,
            overrideFactor: overrideFactor
        )
    }

    @Test("Guard: eventual glucose is not low") func testEventualGlucoseNotLow() throws {
        let (shouldSet, determination) = try callHandleLowEventualGlucose(eventualGlucose: 100, minGlucose: 100)
        #expect(shouldSet == false)
        #expect(determination.reason == "")
    }

    @Test("Naive eventual glucose below 40") func testNaiveEventualGlucoseBelow40() throws {
        let (shouldSet, determination) = try callHandleLowEventualGlucose(
            minDelta: 1,
            expectedDelta: 0,
            carbsRequired: 10,
            naiveEventualGlucose: 39
        )
        #expect(shouldSet == true)
        #expect(determination.rate == 0)
        #expect(determination.duration == 30)
        #expect(determination.reason.contains("naive_eventualBG < 40"))
    }

    @Test("Min delta > expected, but no carbs required") func testMinDeltaGreaterThanExpectedDeltaAndNoCarbs() throws {
        let (shouldSet, _) = try callHandleLowEventualGlucose(minDelta: 1, expectedDelta: 0, carbsRequired: 0)
        #expect(shouldSet == true)
    }

    @Test("Current temp rate matches basal") func testCurrentTempRateMatchesBasal() throws {
        let profile = defaultProfile()
        let currentTemp = TempBasal(duration: 20, rate: profile.currentBasal!, temp: .absolute, timestamp: Date())
        let (shouldSet, determination) = try callHandleLowEventualGlucose(
            minDelta: 1,
            expectedDelta: 0,
            carbsRequired: 10,
            currentTemp: currentTemp,
            profile: profile
        )
        #expect(shouldSet == true)
        #expect(determination.rate == nil) // No change
        #expect(determination.reason.contains("temp \(currentTemp.rate) ~ req \(profile.currentBasal!)U/hr."))
    }

    @Test("Set basal as temp") func testSetBasalAsTemp() throws {
        let profile = defaultProfile()
        let (shouldSet, determination) = try callHandleLowEventualGlucose(
            minDelta: 1,
            expectedDelta: 0,
            carbsRequired: 10,
            profile: profile
        )
        #expect(shouldSet == true)
        #expect(determination.rate == profile.currentBasal)
        #expect(determination.duration == 30)
        #expect(determination.reason.contains("setting current basal of \(profile.currentBasal!) as temp."))
    }

    /*
     @Test("Insulin scheduled less than required") func testInsulinScheduledLessThanRequired() throws {
         let (shouldSet, determination) = try callHandleLowEventualGlucose(
             eventualGlucose: 80,
             naiveEventualGlucose: 70,
             currentTemp: TempBasal(duration: 10, rate: 0, temp: .absolute, timestamp: Date())
         )
         #expect(shouldSet == true)
         #expect(determination.rate != nil)
         #expect(determination.duration == 30)
         #expect(determination.reason.contains("is a lot less than needed"))
     }*/

    /*
     @Test("Rate similar to current temp") func testRateSimilarToCurrentTemp() throws {
         let currentTemp = TempBasal(duration: 10, rate: 0.1, temp: .absolute, timestamp: Date())
         let (shouldSet, determination) = try callHandleLowEventualGlucose(
             eventualGlucose: 99,
             targetGlucose: 110,
             currentTemp: currentTemp,
             adjustedSensitivity: 50
         )

         let insulinRequired = 2 * min(0, (Decimal(99) - Decimal(110)) / Decimal(50))
         let expectedRate = (1.0 + (2 * insulinRequired)).rounded(toPlaces: 2)

         #expect(shouldSet == true)
         #expect(determination.rate == nil) // No change
         #expect(determination.reason.contains("temp \(currentTemp.rate) ~< req \(expectedRate)U/hr."))
     }
      */

    @Test("Set zero temp") func testSetZeroTemp() throws {
        let (shouldSet, determination) = try callHandleLowEventualGlucose(eventualGlucose: 70, naiveEventualGlucose: 60)
        #expect(shouldSet == true)
        #expect(determination.rate == 0)
        #expect(determination.duration! > 0)
        #expect(determination.reason.contains("setting \(determination.duration!)m zero temp."))
    }

    /*
     @Test("Set calculated rate") func testSetCalculatedRate() throws {
         let (shouldSet, determination) = try callHandleLowEventualGlucose(eventualGlucose: 85)
         #expect(shouldSet == true)
         #expect(determination.rate! > 0)
         #expect(determination.duration == 30)
         #expect(determination.reason.contains("setting \(determination.rate!)U/hr."))
     }*/
}
