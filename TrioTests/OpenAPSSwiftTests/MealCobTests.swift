import Foundation
import Testing
@testable import Trio

@Suite("MealCob Tests") struct MealCobTests {
    // Helper function to create basic profile for testing
    func createBasicProfile() -> Profile {
        var profile = Profile()
        profile.dia = 4
        profile.maxMealAbsorptionTime = 6
        profile.min5mCarbImpact = 3
        profile.carbRatio = 10
        profile.currentBasal = 1.0
        profile.isfProfile = ComputedInsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: [ComputedInsulinSensitivityEntry(sensitivity: 40, offset: 0, start: "00:00:00")]
        )
        return profile
    }

    // Helper function to create basal profile
    func createBasalProfile() -> [BasalProfileEntry] {
        [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1.0)]
    }

    // Helper function to create glucose data from values and timestamps
    func createGlucoseData(startTime: Date, values: [Int], intervalMinutes: Int = 5) -> [BloodGlucose] {
        values.enumerated().map { i, glucose in
            let timestamp = startTime.addingTimeInterval(TimeInterval(i * intervalMinutes * 60))
            return BloodGlucose(
                sgv: glucose,
                date: Decimal(timestamp.timeIntervalSince1970 * 1000), // JS uses ms
                dateString: timestamp
            )
        }.reversed()
    }

    @Test("should detect carb absorption with rising glucose") func detectCarbAbsorptionWithRisingGlucose() async throws {
        let mealTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        var carbImpactTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        // Create glucose data showing significant rise after meal
        let glucoseValues = [100, 105, 110, 115, 120, 130, 140, 150, 155, 160, 160, 160, 160]
        let glucoseData = createGlucoseData(startTime: mealTime, values: glucoseValues)

        var profile = createBasicProfile()
        let basalProfile = createBasalProfile()
        let pumpHistory: [PumpHistoryEvent] = []

        // Test with carbImpactTime
        var result = try MealCob.detectCarbAbsorption(
            clock: &carbImpactTime, // no pump events, set to whatever
            glucose: glucoseData,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealTime,
            carbImpactDate: carbImpactTime
        )

        #expect(result.carbsAbsorbed.isWithin(0.01, of: 9.75))

        // Test without carbImpactTime
        result = try MealCob.detectCarbAbsorption(
            clock: &carbImpactTime, // no pump events, set to whatever
            glucose: glucoseData,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealTime,
            carbImpactDate: nil
        )

        #expect(result.carbsAbsorbed.isWithin(0.01, of: 14.75))
    }

    @Test("should handle stable glucose (no carb absorption)") func handleStableGlucose() async throws {
        let mealTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        var carbImpactTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        // Create stable glucose data
        let glucoseValues = [100, 100, 100, 100, 100, 100]
        let glucoseData = createGlucoseData(startTime: mealTime, values: glucoseValues)

        var profile = createBasicProfile()
        let basalProfile = createBasalProfile()
        let pumpHistory: [PumpHistoryEvent] = []

        let result = try MealCob.detectCarbAbsorption(
            clock: &carbImpactTime, // no pump events, set to whatever
            glucose: glucoseData,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealTime,
            carbImpactDate: carbImpactTime
        )

        #expect(result.carbsAbsorbed == 0)
    }

    @Test("should handle falling glucose (negative deviation)") func handleFallingGlucose() async throws {
        let mealTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        var carbImpactTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        // Create falling glucose data: 150 -> 125
        let glucoseValues = [150, 145, 140, 135, 130, 125]
        let glucoseData = createGlucoseData(startTime: mealTime, values: glucoseValues)

        var profile = createBasicProfile()
        let basalProfile = createBasalProfile()
        let pumpHistory: [PumpHistoryEvent] = []

        let result = try MealCob.detectCarbAbsorption(
            clock: &carbImpactTime, // no pump events, set to whatever
            glucose: glucoseData,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealTime,
            carbImpactDate: carbImpactTime
        )

        #expect(result.carbsAbsorbed == 0) // No carbs absorbed when glucose is falling
    }

    @Test("should stop processing when pre-meal BG is found") func stopProcessingWhenPreMealBGFound() async throws {
        let mealTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        var carbImpactTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        // Include glucose data from before meal time
        let glucoseData = [
            BloodGlucose(
                sgv: 150,
                date: Decimal(mealTime.addingTimeInterval(60 * 60).timeIntervalSince1970 * 1000), // 1 hour after meal
                dateString: mealTime.addingTimeInterval(60 * 60)
            ),
            BloodGlucose(
                sgv: 120,
                date: Decimal(mealTime.addingTimeInterval(30 * 60).timeIntervalSince1970 * 1000), // 30 minutes after meal
                dateString: mealTime.addingTimeInterval(30 * 60)
            ),
            BloodGlucose(
                sgv: 100,
                date: Decimal(mealTime.addingTimeInterval(-30 * 60).timeIntervalSince1970 * 1000),
                // 30 minutes before meal (pre-meal)
                dateString: mealTime.addingTimeInterval(-30 * 60)
            )
        ]

        var profile = createBasicProfile()
        let basalProfile = createBasalProfile()
        let pumpHistory: [PumpHistoryEvent] = []

        let result = try MealCob.detectCarbAbsorption(
            clock: &carbImpactTime, // no pump events, set to whatever
            glucose: glucoseData,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealTime,
            carbImpactDate: carbImpactTime
        )

        #expect(result.carbsAbsorbed.isWithin(0.01, of: 3.75))
    }

    @Test("should respect maxMealAbsorptionTime") func respectMaxMealAbsorptionTime() async throws {
        let mealTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        var carbImpactTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        // Create glucose data spanning longer than maxMealAbsorptionTime
        var glucoseValues: [Int] = []
        for i in 0 ..< 100 { // 100 * 5 minutes = ~8 hours
            let value = Int(100 + sin(Double(i) * 0.1) * 20) // Sinusoidal pattern
            glucoseValues.append(value)
        }

        let glucoseData = createGlucoseData(
            startTime: mealTime.addingTimeInterval(-2 * 60 * 60), // Start 2 hours before meal
            values: glucoseValues
        )

        var profile = createBasicProfile()
        profile.maxMealAbsorptionTime = 2 // Only 2 hours
        let basalProfile = createBasalProfile()
        let pumpHistory: [PumpHistoryEvent] = []

        let result = try MealCob.detectCarbAbsorption(
            clock: &carbImpactTime, // no pump events, set to whatever
            glucose: glucoseData,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealTime,
            carbImpactDate: carbImpactTime
        )

        #expect(result.carbsAbsorbed.isWithin(0.01, of: 40.5))
    }

    @Test("should handle minimum carb impact from profile") func handleMinimumCarbImpactFromProfile() async throws {
        var mealTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")

        // Create glucose data with slight rise to trigger carb absorption
        let glucoseValues = [100, 101, 102, 103, 104, 105]
        let glucoseData = createGlucoseData(startTime: mealTime, values: glucoseValues)

        var profile = createBasicProfile()
        profile.min5mCarbImpact = 5 // Higher minimum impact
        let basalProfile = createBasalProfile()
        let pumpHistory: [PumpHistoryEvent] = []

        let result = try MealCob.detectCarbAbsorption(
            clock: &mealTime, // no pump events, set to whatever
            glucose: glucoseData,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealTime,
            carbImpactDate: nil
        )

        #expect(result.carbsAbsorbed.isWithin(0.01, of: 3.75))
    }
}
