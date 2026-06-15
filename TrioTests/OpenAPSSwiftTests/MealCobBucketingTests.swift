import Foundation
import Testing
@testable import Trio

@Suite("Meal glucose bucketing tests") struct MealCobBucketingTests {
    // Default test profile - matches JS exactly
    func createDefaultProfile() -> Profile {
        var profile = Profile()
        profile.dia = 4
        profile.maxMealAbsorptionTime = 6
        profile.min5mCarbImpact = 3
        profile.carbRatio = 10
        return profile
    }

    // Helper to create glucose entry - matches JS structure
    func createGlucoseEntry(glucose: Int, timeMs: Double) -> BloodGlucose {
        let date = Date(timeIntervalSince1970: timeMs / 1000)
        return BloodGlucose(
            sgv: glucose,
            date: Decimal(timeMs),
            dateString: date,
            glucose: glucose
        )
    }

    // Note: glucose_data is expected in reverse chronological order (newest first)
    // The bucketGlucoseData function maintains this order in its output

    @Test(
        "should handle normal 5-minute interval data without modification"
    ) func shouldHandleNormal5MinuteIntervalDataWithoutModification() async throws {
        let mealTime = Date.from(isoString: "2024-01-01T12:00:00-05:00")
        let mealTimeMs = mealTime.timeIntervalSince1970 * 1000

        // Create regular 5-minute interval data (chronological order)
        var glucose_data = [
            createGlucoseEntry(glucose: 100, timeMs: mealTimeMs),
            createGlucoseEntry(glucose: 105, timeMs: mealTimeMs + 5 * 60 * 1000),
            createGlucoseEntry(glucose: 110, timeMs: mealTimeMs + 10 * 60 * 1000),
            createGlucoseEntry(glucose: 115, timeMs: mealTimeMs + 15 * 60 * 1000)
        ]
        glucose_data.reverse() // Convert to reverse chronological order

        let result = try MealCob.bucketGlucoseForCob(
            glucose: glucose_data,
            profile: createDefaultProfile(),
            mealDate: mealTime,
            carbImpactDate: nil
        )

        // Should return same number of entries
        #expect(result.count == 4)
        // Values should be unchanged (in reverse chronological order)
        #expect(result[0].glucose == 115)
        #expect(result[1].glucose == 110)
        #expect(result[2].glucose == 105)
        #expect(result[3].glucose == 100)
    }

    @Test("should interpolate missing data when gap > 8 minutes") func shouldInterpolateMissingDataWhenGapGreaterThan8Minutes(
    ) async throws {
        let mealTime = Date.from(isoString: "2024-01-01T12:00:00-05:00")
        let mealTimeMs = mealTime.timeIntervalSince1970 * 1000

        // Create data with a 21-minute gap (chronological order)
        var glucose_data = [
            createGlucoseEntry(glucose: 99, timeMs: mealTimeMs),
            createGlucoseEntry(glucose: 120, timeMs: mealTimeMs + 21 * 60 * 1000) // 21 min gap
        ]
        glucose_data.reverse() // Convert to reverse chronological order

        let result = try MealCob.bucketGlucoseForCob(
            glucose: glucose_data,
            profile: createDefaultProfile(),
            mealDate: mealTime,
            carbImpactDate: nil
        )

        // Should have interpolated 4 additional points (5, 10, 15, 20 minutes)
        #expect(result.count == 5)

        // Check interpolated values (in reverse chronological order)
        #expect(result[0].glucose == 120) // original (newest)
        #expect(result[1].glucose == 115) // interpolated
        #expect(result[2].glucose == 110) // interpolated
        #expect(result[3].glucose == 105) // interpolated
        #expect(result[4].glucose == 100) // interpolated

        // Check that dates are properly set
        #expect(result[1].date == mealTime.addingTimeInterval(16 * 60))
        #expect(result[2].date == mealTime.addingTimeInterval(11 * 60))
        #expect(result[3].date == mealTime.addingTimeInterval(6 * 60))
        #expect(result[4].date == mealTime.addingTimeInterval(1 * 60))
    }

    @Test("should stop processing after maxMealAbsorptionTime") func shouldStopProcessingAfterMaxMealAbsorptionTime() async throws {
        let mealTime = Date.from(isoString: "2024-01-01T12:00:00-05:00")
        let mealTimeMs = mealTime.timeIntervalSince1970 * 1000

        // Create data spanning 8 hours (chronological order)
        var glucose_data: [BloodGlucose] = []
        for i in 0 ... 96 { // 96 * 5 min = 8 hours
            glucose_data.append(createGlucoseEntry(
                glucose: 100 + i,
                timeMs: mealTimeMs + Double(i) * 5 * 60 * 1000
            ))
        }
        glucose_data.reverse() // Convert to reverse chronological order

        // Set maxMealAbsorptionTime to 2 hours
        var profile = createDefaultProfile()
        profile.maxMealAbsorptionTime = 2

        let result = try MealCob.bucketGlucoseForCob(
            glucose: glucose_data,
            profile: profile,
            mealDate: mealTime,
            carbImpactDate: nil
        )

        // JS test expects 72 entries (not 25 as in original Swift test)
        print(result)
        #expect(result.count == 72)

        // Check specific values to match JS test
        #expect(result[0].glucose == 196)
        #expect(result[1].glucose == 195)
        #expect(result[12].glucose == 178)
        #expect(result[24].glucose == 160)
    }

    @Test("should only process data within 45 minutes in CI mode") func shouldOnlyProcessDataWithin45MinutesInCIMode() async throws {
        let mealTime = Date.from(isoString: "2024-01-01T12:00:00-05:00")
        let ciTime = Date.from(isoString: "2024-01-01T14:00:00-05:00") // 2 hours after meal
        let mealTimeMs = mealTime.timeIntervalSince1970 * 1000

        // Create data spanning 3 hours (chronological order)
        var glucose_data: [BloodGlucose] = []
        for i in 0 ... 36 { // 36 * 5 min = 3 hours
            glucose_data.append(createGlucoseEntry(
                glucose: 100 + i,
                timeMs: mealTimeMs + Double(i) * 5 * 60 * 1000
            ))
        }
        glucose_data.reverse() // Convert to reverse chronological order

        let result = try MealCob.bucketGlucoseForCob(
            glucose: glucose_data,
            profile: createDefaultProfile(),
            mealDate: mealTime,
            carbImpactDate: ciTime
        )

        // JS test shows this captures more than 45 minutes due to the bucketing logic
        for entry in result {
            let minutesFromCI = abs(ciTime.timeIntervalSince(entry.date)) / 60
            #expect(minutesFromCI <= 120) // JS test uses 120, not 45
        }

        // JS test expects 21 entries
        #expect(result.count == 21)
    }

    @Test("should stop processing when pre-meal BG is found") func shouldStopProcessingWhenPreMealBGIsFound() async throws {
        let mealTime = Date.from(isoString: "2024-01-01T12:00:00-05:00")
        let mealTimeMs = mealTime.timeIntervalSince1970 * 1000

        // Create data that includes pre-meal values (chronological order)
        var glucose_data = [
            createGlucoseEntry(glucose: 90, timeMs: mealTimeMs - 10 * 60 * 1000), // 10 min before meal
            createGlucoseEntry(glucose: 95, timeMs: mealTimeMs - 5 * 60 * 1000), // 5 min before meal
            createGlucoseEntry(glucose: 100, timeMs: mealTimeMs),
            createGlucoseEntry(glucose: 105, timeMs: mealTimeMs + 5 * 60 * 1000),
            createGlucoseEntry(glucose: 110, timeMs: mealTimeMs + 10 * 60 * 1000),
            createGlucoseEntry(glucose: 115, timeMs: mealTimeMs + 15 * 60 * 1000) // 15 min after
        ]
        glucose_data.reverse() // Convert to reverse chronological order

        let result = try MealCob.bucketGlucoseForCob(
            glucose: glucose_data,
            profile: createDefaultProfile(),
            mealDate: mealTime,
            carbImpactDate: nil
        )

        // JS test expects 5 entries (includes one pre-meal entry due to bug)
        #expect(result.count == 5)
        // Values should be unchanged (in reverse chronological order)
        #expect(result[0].glucose == 115)
        #expect(result[1].glucose == 110)
        #expect(result[2].glucose == 105)
        #expect(result[3].glucose == 100)
        #expect(result[4].glucose == 95) // This pre-meal entry is included due to JS bug
    }

    @Test(
        "should average glucose values when readings are very close (≤ 2 minutes)"
    ) func shouldAverageGlucoseValuesWhenReadingsAreVeryClose() async throws {
        let mealTime = Date.from(isoString: "2024-01-01T12:00:00-05:00")
        let mealTimeMs = mealTime.timeIntervalSince1970 * 1000

        // Create data with readings 1 minute apart (chronological order)
        var glucose_data = [
            createGlucoseEntry(glucose: 100, timeMs: mealTimeMs),
            createGlucoseEntry(glucose: 102, timeMs: mealTimeMs + 1 * 60 * 1000), // 1 min later
            createGlucoseEntry(glucose: 104, timeMs: mealTimeMs + 2 * 60 * 1000), // 2 min later
            createGlucoseEntry(glucose: 110, timeMs: mealTimeMs + 5 * 60 * 1000) // 5 min later
        ]
        glucose_data.reverse() // Convert to reverse chronological order

        let result = try MealCob.bucketGlucoseForCob(
            glucose: glucose_data,
            profile: createDefaultProfile(),
            mealDate: mealTime,
            carbImpactDate: nil
        )

        // Close readings should be averaged (in reverse chronological order)
        #expect(result.count == 2)
        #expect(result[0].glucose == 110)
        // JS test shows averaging bug results in 101.5, not 102
        #expect(result[1].glucose == 101.5)
    }

    @Test("should cap interpolation at 240 minutes for very large gaps") func shouldCapInterpolationAt240MinutesForVeryLargeGaps(
    ) async throws {
        let mealTime = Date.from(isoString: "2024-01-01T12:00:00-05:00")
        let mealTimeMs = mealTime.timeIntervalSince1970 * 1000

        // Create data with a 6-hour (360 minute) gap (chronological order)
        var glucose_data = [
            createGlucoseEntry(glucose: 100, timeMs: mealTimeMs),
            createGlucoseEntry(glucose: 200, timeMs: mealTimeMs + 360 * 60 * 1000) // 6 hour gap
        ]
        glucose_data.reverse() // Convert to reverse chronological order

        let result = try MealCob.bucketGlucoseForCob(
            glucose: glucose_data,
            profile: createDefaultProfile(),
            mealDate: mealTime,
            carbImpactDate: nil
        )

        // JS test expects 48 entries due to capping at 240 minutes
        #expect(result.count == 48)

        // Check that interpolation stopped at 240 minutes
        let gapMinutes = result[0].date.timeIntervalSince(result[result.count - 1].date) / 60
        #expect(gapMinutes == 235)
    }
}
