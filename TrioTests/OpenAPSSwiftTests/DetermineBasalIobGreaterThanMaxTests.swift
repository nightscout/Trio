
import Foundation
import Testing
@testable import Trio

/// These tests should be an exact copy of the JS tests here:
/// - https://github.com/kingst/trio-oref/blob/dev-fixes-for-swift-comparison/tests/determine-basal-iob-greater-than-max.test.js
@Suite("DosingEngine.iobGreaterThanMax") struct DetermineBasalIobGreaterThanMaxTests {
    private func defaultProfile() -> Profile {
        var profile = Profile()
        profile.maxIob = 1.5
        profile.currentBasal = 1.0
        profile.maxBasal = 1.5
        profile.maxDailyBasal = 3.5
        profile.outUnits = .mgdL
        return profile
    }

    private func callIobGreaterThanMax(
        iob: Decimal = 1.5,
        maxIob: Decimal? = nil,
        currentTemp: TempBasal = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date()),
        basal: Decimal? = nil,
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

        return try DosingEngine.iobGreaterThanMax(
            iob: iob,
            maxIob: maxIob ?? testProfile.maxIob,
            currentTemp: currentTemp,
            basal: basal ?? testProfile.currentBasal!,
            profile: testProfile,
            determination: testDetermination
        )
    }

    @Test("Guard: iob not greater than max") func testIobNotGreaterThanMax() throws {
        let (shouldSet, determination) = try callIobGreaterThanMax(iob: 1.5, maxIob: 1.5)
        #expect(shouldSet == false)
        #expect(determination.reason == "")
    }

    @Test("Continue current temp") func testContinueCurrentTemp() throws {
        let profile = defaultProfile()
        let currentTemp = TempBasal(duration: 20, rate: profile.currentBasal!, temp: .absolute, timestamp: Date())
        let (shouldSet, determination) = try callIobGreaterThanMax(
            iob: 1.6,
            currentTemp: currentTemp,
            basal: profile.currentBasal!,
            profile: profile
        )
        #expect(shouldSet == true)
        #expect(determination.rate == nil) // No change
        #expect(determination.reason.contains("temp \(currentTemp.rate) ~ req \(profile.currentBasal!)U/hr."))
    }

    @Test("Set new temp when duration is short") func testSetNewTempDurationShort() throws {
        let profile = defaultProfile()
        let currentTemp = TempBasal(duration: 10, rate: 1.0, temp: .absolute, timestamp: Date())
        let basal: Decimal = 1.2
        let (shouldSet, determination) = try callIobGreaterThanMax(
            iob: 1.6,
            currentTemp: currentTemp,
            basal: basal,
            profile: profile
        )
        #expect(shouldSet == true)
        #expect(determination.rate == basal)
        #expect(determination.duration == 30)
        #expect(determination.reason.contains("setting current basal of \(basal) as temp."))
    }

    @Test("Set new temp when rates differ") func testSetNewTempRatesDiffer() throws {
        let profile = defaultProfile()
        let currentTemp = TempBasal(duration: 20, rate: 1.0, temp: .absolute, timestamp: Date())
        let basal: Decimal = 1.2
        let (shouldSet, determination) = try callIobGreaterThanMax(
            iob: 1.6,
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
