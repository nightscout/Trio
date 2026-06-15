import Foundation
import Testing
@testable import Trio

/// A direct port of the Javascript `set-temp-basal.test.js` tests
@Suite("Set Temp Basal Tests") struct SetTempBasalTests {
    /// Helper to create a default profile for tests.
    private func createProfile(
        currentBasal: Decimal = 0.8,
        maxDailyBasal: Decimal = 1.3,
        maxBasal: Decimal = 3.0,
        skipNeutralTemps: Bool = false,
        maxDailySafetyMultiplier: Decimal = 3,
        currentBasalSafetyMultiplier: Decimal = 4,
        model: String? = nil
    ) -> Profile {
        var profile = Profile()
        profile.currentBasal = currentBasal
        profile.maxDailyBasal = maxDailyBasal
        profile.maxBasal = maxBasal
        profile.skipNeutralTemps = skipNeutralTemps
        profile.maxDailySafetyMultiplier = maxDailySafetyMultiplier
        profile.currentBasalSafetyMultiplier = currentBasalSafetyMultiplier
        profile.model = model
        return profile
    }

    /// Helper to create a default determination object.
    private func createDetermination() -> Determination {
        Determination(
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
            deliverAt: Date(),
            carbsReq: nil,
            temp: .absolute,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: Date(),
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: false
        )
    }

    /// Helper to create a TempBasal object
    private func createCurrentTemp(rate: Decimal = 0, duration: Decimal = 0) -> TempBasal {
        TempBasal(
            duration: Int(truncating: duration as NSNumber),
            rate: rate,
            temp: .absolute,
            timestamp: Date()
        )
    }

    @Test("should cancel temp") func cancelTemp() throws {
        let profile = createProfile()
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 0,
            duration: 0,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 0)
        #expect(requestedTemp.duration == 0)
    }

    @Test("should set zero temp") func setZeroTemp() throws {
        let profile = createProfile()
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 0,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 0)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should set high temp") func setHighTemp() throws {
        let profile = createProfile()
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 2,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 2)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should not set basal on skip neutral mode") func skipNeutralMode() throws {
        // Test case 1: Current temp is active
        var profile = createProfile(currentBasal: 0.8, skipNeutralTemps: true)
        var determination = createDetermination()
        var currentTemp = createCurrentTemp(duration: 10)

        var requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 0.8,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.duration == 0)

        // Test case 2: No current temp
        determination = createDetermination()
        currentTemp = createCurrentTemp() // duration = 0
        requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 0.8,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.reason.contains("no temp basal is active, doing nothing") == true)
    }

    @Test("should limit high temp to max_basal") func limitToMaxBasal() throws {
        let profile = createProfile(maxBasal: 3.0)
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 4,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 3.0)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should limit high temp to 3 * max_daily_basal") func limitToMaxDailyBasal() throws {
        let profile = createProfile(currentBasal: 1.0, maxDailyBasal: 1.3, maxBasal: 10.0)
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 6,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 3.9)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should limit high temp to 4 * current_basal") func limitToCurrentBasal() throws {
        let profile = createProfile(currentBasal: 0.7, maxDailyBasal: 1.3, maxBasal: 10.0)
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 6,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 2.8)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should temp to 0 when requested rate is less than 0") func rateLessThanZero() throws {
        let profile = createProfile(currentBasal: 0.7, maxDailyBasal: 1.3, maxBasal: 10.0)
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: -1,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 0)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should limit high temp to 4 * max_daily_basal when overridden") func limitWithOverrideMaxDaily() throws {
        let profile = createProfile(currentBasal: 2.0, maxDailyBasal: 1.3, maxBasal: 10.0, maxDailySafetyMultiplier: 4)
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 6,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 5.2)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should limit high temp to 5 * current_basal when overridden") func limitWithOverrideCurrentBasal() throws {
        let profile = createProfile(currentBasal: 0.7, maxDailyBasal: 1.3, maxBasal: 10.0, currentBasalSafetyMultiplier: 5)
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 6,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 3.5)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should allow small basal change when current temp is also small") func allowSmallChange() throws {
        let profile = createProfile(
            currentBasal: 0.075,
            maxDailyBasal: 1.3,
            maxBasal: 10.0,
            currentBasalSafetyMultiplier: 5,
            model: "523"
        )
        let determination = createDetermination()
        let currentTemp = createCurrentTemp(rate: 0.025, duration: 24)

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 0,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.rate == 0)
        #expect(requestedTemp.duration == 30)
    }

    @Test("should not allow small basal change when current temp is large") func disallowSmallChange() throws {
        let profile = createProfile(
            currentBasal: 10.075,
            maxDailyBasal: 11.3,
            maxBasal: 50.0,
            currentBasalSafetyMultiplier: 5,
            model: "523"
        )
        let determination = createDetermination()
        let currentTemp = createCurrentTemp(rate: 10.1, duration: 24)

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 10.125,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )
        #expect(requestedTemp.reason.contains("no temp required") == true)
    }

    @Test("should set neutral temp") func setNeutralTemp() throws {
        let profile = createProfile(currentBasal: 0.8, skipNeutralTemps: false)
        let determination = createDetermination()
        let currentTemp = createCurrentTemp()

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 0.8,
            duration: 30,
            profile: profile,
            determination: determination,
            currentTemp: currentTemp
        )

        #expect(requestedTemp.rate == 0.8)
        #expect(requestedTemp.duration == 30)
        #expect(requestedTemp.reason == ". Setting neutral temp basal of 0.8U/hr")
    }
}
