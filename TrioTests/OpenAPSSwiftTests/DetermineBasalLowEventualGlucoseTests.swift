import Foundation
import Testing
@testable import Trio

/// these tests should be an exact copy of the JS tests here:
/// - https://github.com/kingst/trio-oref/blob/dev-fixes-for-swift-comparison/tests/determine-basal-low-eventual-glucose.test.js
/// We had to extract the key functionality from JS and put it in a function to facilitate testing
@Suite("DetermineBasal low eventual glucose") struct HandleLowEventualGlucoseTests {
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
            carbsRequired: 0,
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

    @Test("Min delta < 0") func testMinDeltaLessThanZero() throws {
        let (shouldSet, determination) = try callHandleLowEventualGlucose(minDelta: -1, expectedDelta: -2, carbsRequired: 0)
        #expect(shouldSet == true)
        #expect(determination.rate == 0.6)
    }

    @Test("Current temp rate matches basal") func testCurrentTempRateMatchesBasal() throws {
        let profile = defaultProfile()
        let currentTemp = TempBasal(duration: 20, rate: profile.currentBasal!, temp: .absolute, timestamp: Date())
        let (shouldSet, determination) = try callHandleLowEventualGlucose(
            minDelta: 1,
            expectedDelta: 0,
            carbsRequired: 0,
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
            carbsRequired: 0,
            profile: profile
        )
        #expect(shouldSet == true)
        #expect(determination.rate == profile.currentBasal)
        #expect(determination.duration == 30)
        #expect(determination.reason.contains("setting current basal of \(profile.currentBasal!) as temp."))
    }

    @Test("Insulin scheduled less than required") func testInsulinScheduledLessThanRequired() throws {
        let (shouldSet, determination) = try callHandleLowEventualGlucose(
            eventualGlucose: 80,
            naiveEventualGlucose: 70,
            currentTemp: TempBasal(duration: 120, rate: 0, temp: .absolute, timestamp: Date())
        )
        #expect(shouldSet == true)
        #expect(determination.rate == nil)
        #expect(determination.duration == nil)
        #expect(determination.reason.contains("is a lot less than needed"))
    }

    @Test("Rate similar to current temp") func testRateSimilarToCurrentTemp() throws {
        let currentTemp = TempBasal(duration: 10, rate: 0.1, temp: .absolute, timestamp: Date())
        let (shouldSet, determination) = try callHandleLowEventualGlucose(
            eventualGlucose: 99,
            targetGlucose: 110,
            currentTemp: currentTemp,
            adjustedSensitivity: 50
        )

        #expect(shouldSet == true)
        #expect(determination.rate == nil) // No change
        #expect(determination.reason.contains("temp \(currentTemp.rate) ~< req"))
    }

    @Test("Set zero temp") func testSetZeroTemp() throws {
        let (shouldSet, determination) = try callHandleLowEventualGlucose(eventualGlucose: 70, naiveEventualGlucose: 60)
        #expect(shouldSet == true)
        #expect(determination.rate == 0)
        #expect(determination.duration! > 0)
        #expect(determination.reason.contains("setting \(determination.duration!)m zero temp."))
    }
}
