
import Foundation
import Testing
@testable import Trio

/// These tests should be an exact copy of the JS tests here:
/// - https://github.com/kingst/trio-oref/blob/dev-fixes-for-swift-comparison/tests/determine-basal-glucose-falling-faster-than-expected.test.js
@Suite("DosingEngine.glucoseFallingFasterThanExpected") struct DetermineBasalGlucoseFallingFasterThanExpectedTests {
    private func defaultProfile() -> Profile {
        var profile = Profile()
        profile.minBg = 90
        profile.targetBg = 100
        profile.currentBasal = 1.0
        profile.maxDailyBasal = 1.3
        profile.maxBasal = 3.5
        profile.sens = 50
        profile.outUnits = .mgdL
        return profile
    }

    private func defaultGlucoseStatus() -> GlucoseStatus {
        GlucoseStatus(
            delta: 5,
            glucose: 100,
            noise: 1,
            shortAvgDelta: 0,
            longAvgDelta: 0,
            date: Date(),
            lastCalIndex: nil,
            device: "test"
        )
    }

    private func callGlucoseFallingFasterThanExpected(
        eventualGlucose: Decimal = 100,
        minGlucose: Decimal? = nil,
        minDelta: Decimal = 4,
        expectedDelta: Decimal = 5,
        glucoseStatus: GlucoseStatus? = nil,
        currentTemp: TempBasal = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date()),
        basal: Decimal? = nil,
        smbIsEnabled: Bool = false,
        profile: Profile? = nil,
        determination: Determination? = nil
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

        return try DosingEngine.glucoseFallingFasterThanExpected(
            eventualGlucose: eventualGlucose,
            minGlucose: minGlucose ?? testProfile.minBg!,
            minDelta: minDelta,
            expectedDelta: expectedDelta,
            glucoseStatus: glucoseStatus ?? defaultGlucoseStatus(),
            currentTemp: currentTemp,
            basal: basal ?? testProfile.currentBasal!,
            smbIsEnabled: smbIsEnabled,
            profile: testProfile,
            determination: testDetermination
        )
    }

    @Test("Guard: minDelta not less than expectedDelta") func testMinDeltaNotLessThanExpected() throws {
        let (shouldSet, determination) = try callGlucoseFallingFasterThanExpected(minDelta: 5, expectedDelta: 5)
        #expect(shouldSet == false)
        #expect(determination.reason == "")
    }

    @Test("Guard: SMB is enabled") func testSmbIsEnabled() throws {
        let (shouldSet, determination) = try callGlucoseFallingFasterThanExpected(smbIsEnabled: true)
        #expect(shouldSet == false)
        #expect(determination.reason == "")
    }

    @Test("Continue current temp") func testContinueCurrentTemp() throws {
        let profile = defaultProfile()
        let currentTemp = TempBasal(duration: 20, rate: profile.currentBasal!, temp: .absolute, timestamp: Date())
        let (shouldSet, determination) = try callGlucoseFallingFasterThanExpected(
            currentTemp: currentTemp,
            basal: profile.currentBasal!,
            profile: profile
        )
        #expect(shouldSet == true)
        #expect(determination.rate == nil) // No change
        #expect(determination.reason.contains("temp \(currentTemp.rate) ~ req \(profile.currentBasal!)U/hr."))
    }

    @Test("Set new temp") func testSetNewTemp() throws {
        let profile = defaultProfile()
        let currentTemp = TempBasal(duration: 10, rate: 1.0, temp: .absolute, timestamp: Date())
        let basal: Decimal = 1.2
        let (shouldSet, determination) = try callGlucoseFallingFasterThanExpected(
            currentTemp: currentTemp,
            basal: basal,
            profile: profile
        )
        #expect(shouldSet == true)
        #expect(determination.rate == basal)
        #expect(determination.duration == 30)
        #expect(determination.reason.contains("setting current basal of \(basal) as temp."))
    }
}
