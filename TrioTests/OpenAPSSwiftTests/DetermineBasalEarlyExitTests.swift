import Foundation
import Testing
@testable import Trio

@Suite("DetermineBasal early exits before core dosing logic") struct DetermineBasalEarlyExitTests {
    private func createDefaultInputs(currentTime: Date = Date()) -> (
        profile: Profile,
        preferences: Preferences,
        currentTemp: TempBasal,
        iobData: [IobResult],
        mealData: ComputedCarbs,
        autosensData: Autosens,
        reservoirData: Decimal,
        glucoseStatus: GlucoseStatus,
        microBolusAllowed: Bool,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        currentTime: Date
    ) {
        var profile = Profile()
        profile.maxIob = 2.5
        profile.dia = 3
        profile.currentBasal = 0.9
        profile.maxDailyBasal = 1.3
        profile.maxBasal = 3.5
        profile.maxBg = 120
        profile.minBg = 110
        profile.sens = 40
        profile.carbRatio = 10
        profile.thresholdSetting = 80
        profile.temptargetSet = false
        profile.bolusIncrement = 0.1
        profile.useCustomPeakTime = false
        profile.curve = .rapidActing

        var preferences = Preferences()
        preferences.useNewFormula = false
        preferences.sigmoid = false
        preferences.adjustmentFactor = 0.8
        preferences.adjustmentFactorSigmoid = 0.5
        preferences.curve = .rapidActing
        preferences.useCustomPeakTime = false

        let currentTemp = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: currentTime)

        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: currentTime,
            iobWithZeroTemp: IobResult.IobWithZeroTemp(
                iob: 0,
                activity: 0,
                basaliob: 0,
                bolusiob: 0,
                netbasalinsulin: 0,
                bolusinsulin: 0,
                time: currentTime
            ),
            lastBolusTime: nil,
            lastTemp: IobResult.LastTemp(
                rate: 0,
                timestamp: currentTime,
                started_at: currentTime,
                date: UInt64(currentTime.timeIntervalSince1970 * 1000),
                duration: 30
            )
        )]

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
            uamMinutes: 30
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
            microBolusAllowed: true,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )
    }

    // Test 1 from JS
    @Test("should fail if current_basal is missing") func missingCurrentBasal() throws {
        var (
            profile,
            preferences,
            currentTemp,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            glucoseStatus,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        profile.currentBasal = nil
        profile.basalprofile = [] // ensure basalFor also returns nil

        #expect(throws: DeterminationError.missingCurrentBasal) {
            _ = try DeterminationGenerator.determineBasal(
                profile: profile,
                preferences: preferences,
                currentTemp: currentTemp,
                iobData: iobData,
                mealData: mealData,
                autosensData: autosensData,
                reservoirData: reservoirData,
                glucoseStatus: glucoseStatus,
                microBolusAllowed: microBolusAllowed,
                trioCustomOrefVariables: trioCustomOrefVariables,
                currentTime: currentTime
            )
        }
    }

    // Test 2 from JS
    @Test("should cancel high temp if BG is 38") func cancelHighTempBG38() throws {
        let (
            profile,
            preferences,
            _,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            _,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        let glucoseStatus = GlucoseStatus(
            delta: 0,
            glucose: 38,
            noise: 1,
            shortAvgDelta: 0,
            longAvgDelta: 0.1,
            date: currentTime,
            lastCalIndex: nil,
            device: "test"
        )

        let currentTemp = TempBasal(duration: 30, rate: 1.5, temp: .absolute, timestamp: currentTime)

        let result = try DeterminationGenerator.determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )

        #expect(result?.rate == profile.currentBasal)
        #expect(result?.duration == 30)
        #expect(result?.reason.contains("Replacing high temp basal") == true)
    }

    // Test 3 from JS
    @Test("should shorten long zero temp if BG data is too old") func shortenLongZeroTempTooOldBG() throws {
        let (
            profile,
            preferences,
            _,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            _,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        let glucoseTime = currentTime.addingTimeInterval(-15 * 60)
        let glucoseStatus = GlucoseStatus(
            delta: 0,
            glucose: 115,
            noise: 1,
            shortAvgDelta: 0,
            longAvgDelta: 0.1,
            date: glucoseTime,
            lastCalIndex: nil,
            device: "test"
        )

        let currentTemp = TempBasal(duration: 60, rate: 0, temp: .absolute, timestamp: currentTime)

        let result = try DeterminationGenerator.determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )

        #expect(result?.rate == 0)
        #expect(result?.duration == 30)
        #expect(result?.reason.contains("Shortening") == true)
    }

    // Test 4 from JS
    @Test("should do nothing if BG is too old and temp is not high") func doNothingOldBGNotHighTemp() throws {
        let (
            profile,
            preferences,
            _,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            _,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        let glucoseTime = currentTime.addingTimeInterval(-15 * 60)
        let glucoseStatus = GlucoseStatus(
            delta: 0,
            glucose: 115,
            noise: 1,
            shortAvgDelta: 0,
            longAvgDelta: 0.1,
            date: glucoseTime,
            lastCalIndex: nil,
            device: "test"
        )

        let currentTemp = TempBasal(duration: 30, rate: 0.5, temp: .absolute, timestamp: currentTime)

        let result = try DeterminationGenerator.determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )

        #expect(result?.rate == nil)
        #expect(result?.duration == nil)
        #expect(result?.reason.contains("doing nothing") == true)
    }

    // Test 5 from JS
    @Test("should error if target_bg cannot be determined") func errorIfTargetBGMissing() throws {
        var (
            profile,
            preferences,
            currentTemp,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            glucoseStatus,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        profile.minBg = nil

        #expect(throws: DeterminationError.invalidProfileTarget) {
            _ = try DeterminationGenerator.determineBasal(
                profile: profile,
                preferences: preferences,
                currentTemp: currentTemp,
                iobData: iobData,
                mealData: mealData,
                autosensData: autosensData,
                reservoirData: reservoirData,
                glucoseStatus: glucoseStatus,
                microBolusAllowed: microBolusAllowed,
                trioCustomOrefVariables: trioCustomOrefVariables,
                currentTime: currentTime
            )
        }
    }

    // Test 6 from JS
    @Test("should cancel temp if currenttemp and lastTemp from pumphistory do not match") func cancelTempMismatch() throws {
        let (
            profile,
            preferences,
            _,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            glucoseStatus,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        let currentTemp = TempBasal(duration: 30, rate: 1.5, temp: .absolute, timestamp: currentTime)

        let lastTempTime = currentTime.addingTimeInterval(-15 * 60)
        let lastTemp = IobResult.LastTemp(
            rate: 1.0,
            timestamp: lastTempTime,
            started_at: lastTempTime,
            date: UInt64(lastTempTime.timeIntervalSince1970 * 1000),
            duration: 30
        )

        var mutableIobData = iobData
        mutableIobData[0].lastTemp = lastTemp

        let result = try DeterminationGenerator.determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: mutableIobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )

        #expect(result?.rate == 0)
        #expect(result?.duration == 0)
        // Note: In swift we use a different reason then JS
        #expect(
            result?
                .reason ==
                "Warning: currenttemp rate 1.5 != lastTemp rate 1 from pumphistory; canceling temp"
        )
    }

    // Test 7 from JS
    @Test("should cancel temp if lastTemp from pumphistory ended long ago") func cancelTempOldLastTemp() throws {
        let (
            profile,
            preferences,
            _,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            glucoseStatus,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        let currentTemp = TempBasal(duration: 30, rate: 1.5, temp: .absolute, timestamp: currentTime)

        let lastTempTime = currentTime.addingTimeInterval(-40 * 60)
        let lastTemp = IobResult.LastTemp(
            rate: 1.5,
            timestamp: lastTempTime,
            started_at: lastTempTime,
            date: UInt64(lastTempTime.timeIntervalSince1970 * 1000),
            duration: 30
        )

        var mutableIobData = iobData
        mutableIobData[0].lastTemp = lastTemp

        let result = try DeterminationGenerator.determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: mutableIobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )

        #expect(result?.rate == 0)
        #expect(result?.duration == 0)
        // Note: In swift we use a different reason then JS
        #expect(
            result?
                .reason == "Warning: currenttemp running but lastTemp from pumphistory ended 10m ago; canceling temp"
        )
    }

    // Test 8 from JS
    @Test("should throw error if eventualBG cannot be calculated") func eventualBGNaN() throws {
        var (
            profile,
            preferences,
            currentTemp,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            glucoseStatus,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()
        profile.sens = .nan

        #expect(throws: DeterminationError.eventualGlucoseCalculationError(sensitivity: .nan, deviation: .nan)) {
            _ = try DeterminationGenerator.determineBasal(
                profile: profile,
                preferences: preferences,
                currentTemp: currentTemp,
                iobData: iobData,
                mealData: mealData,
                autosensData: autosensData,
                reservoirData: reservoirData,
                glucoseStatus: glucoseStatus,
                microBolusAllowed: microBolusAllowed,
                trioCustomOrefVariables: trioCustomOrefVariables,
                currentTime: currentTime
            )
        }
    }

    // Test 9 from JS
    @Test("should low-temp if BG is below threshold") func lowGlucoseSuspend() throws {
        let (
            profile,
            preferences,
            currentTemp,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            _,
            microBolusAllowed,
            trioCustomOrefVariables,
            currentTime
        ) = createDefaultInputs()

        let glucoseStatus = GlucoseStatus(
            delta: 0,
            glucose: 70,
            noise: 1,
            shortAvgDelta: 0,
            longAvgDelta: 0.1,
            date: currentTime,
            lastCalIndex: nil,
            device: "test"
        )

        let result = try DeterminationGenerator.determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )

        #expect(result?.rate == 0)
        #expect((result?.duration ?? 0) >= 30)
        #expect(result?.reason.contains("minGuardBG") == true)
    }

    // Test 10 from JS
    @Test("should cancel temp before the hour if not doing SMB") func skipNeutralTemp() throws {
        // Create a date that is 56 minutes past the hour
        var components = Calendar.current.dateComponents(in: .current, from: Date())
        components.minute = 56
        let currentTime = Calendar.current.date(from: components)!

        var (
            profile,
            preferences,
            currentTemp,
            iobData,
            mealData,
            autosensData,
            reservoirData,
            glucoseStatus,
            microBolusAllowed,
            trioCustomOrefVariables,
            _
        ) = createDefaultInputs(currentTime: currentTime)

        profile.skipNeutralTemps = true

        let result = try DeterminationGenerator.determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )

        #expect(result?.rate == 0)
        #expect(result?.duration == 0)
        #expect(result?.reason.contains("Canceling temp") == true)
    }
}
