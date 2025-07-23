import Foundation
import Testing
@testable import Trio

@Suite("MealTotal Tests") struct MealTotalTests {
    // Helper methods for testing
    func createBasicProfile() -> Profile {
        var profile = Profile()
        profile.dia = 4
        profile.maxMealAbsorptionTime = 6
        profile.maxCOB = 120
        // profile.carbsAbsorptionRate = 30
        profile.min5mCarbImpact = 3
        profile.carbRatio = 10
        profile.currentBasal = 1.0
        // Note: In Swift we need to set sensitivities differently than in JS
        profile
            .isfProfile = ComputedInsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: [ComputedInsulinSensitivityEntry(sensitivity: 40, offset: 0, start: "00:00:00")]
            )
        return profile
    }

    func createBasicBasalProfile() -> [BasalProfileEntry] {
        [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1.0)]
    }

    func createGlucoseData(baseTime: Date, pattern: [Int]) -> [BloodGlucose] {
        var result: [BloodGlucose] = []

        for (i, bg) in pattern.enumerated() {
            let timestamp = baseTime.addingTimeInterval(TimeInterval(i * 5 * 60))

            result.append(BloodGlucose(
                sgv: bg,
                date: Decimal(timestamp.timeIntervalSince1970 * 1000), // JS uses ms
                dateString: timestamp
            ))
        }

        return result.reversed()
    }

    @Test("should calculate carb absorption correctly") func calculateCarbAbsorption() async throws {
        let baseTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        let mealTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        let testTime = Date.from(isoString: "2016-06-19T13:00:00-04:00") // 1 hour after meal

        // Create glucose data showing rise after carbs
        var bgValues = Array(repeating: 100, count: 13)
        for i in 3 ..< 8 {
            bgValues[i] = 100 + ((i - 2) * 10) // 100, 110, 120, 130, 140
        }
        for i in 8 ..< 13 {
            bgValues[i] = 150 // plateau
        }

        let glucoseData = createGlucoseData(baseTime: baseTime, pattern: bgValues)

        // Create insulin data - bolus at same time as carbs
        let pumpHistory = [
            PumpHistoryEvent(
                id: UUID().uuidString,
                type: .bolus,
                timestamp: mealTime,
                amount: 3.0
            )
        ]

        // Carb treatment
        let treatments = [
            MealInput(
                timestamp: mealTime,
                carbs: 30,
                bolus: nil
            )
        ]

        let profile = createBasicProfile()

        let basalProfile = createBasicBasalProfile()

        let result = try MealTotal.recentCarbs(
            treatments: treatments,
            pumpHistory: pumpHistory,
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseData,
            time: testTime
        )

        // After 1 hour, we should see partial carb absorption
        #expect(result != nil)
        // at this level JS is rounding, thus the 0.5
        #expect(result!.mealCOB.isWithin(0.5, of: 10) == true, "mealCOB: \(result!.mealCOB.description)")
        #expect(
            result!.currentDeviation == 3.6,
            "currentDeviation: \(result!.currentDeviation!.description)"
        )
    }

    @Test("should return nil when no treatments provided") func emptyObjectWhenNoTreatments() async throws {
        let time = Date.from(isoString: "2016-06-19T13:00:00-04:00")
        let glucoseData = [
            BloodGlucose(
                sgv: 100,
                date: Decimal(time.timeIntervalSince1970 * 1000),
                dateString: time
            )
        ]

        let profile = createBasicProfile()
        let basalProfile = createBasicBasalProfile()

        let result = try MealTotal.recentCarbs(
            treatments: [],
            pumpHistory: [],
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseData,
            time: time
        )

        #expect(result == nil)
    }

    @Test("should calculate carbs correctly for treatments within the meal window") func calcCarbsWithinMealWindow() async throws {
        let baseTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        let testTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        let treatments = [
            MealInput(
                timestamp: baseTime,
                carbs: 20,
                bolus: nil
            )
        ]

        // Create glucose pattern with slight rise
        let glucoseData = [
            BloodGlucose(
                sgv: 110,
                date: Decimal(baseTime.addingTimeInterval(60 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(60 * 60)
            ),
            BloodGlucose(
                sgv: 105,
                date: Decimal(baseTime.addingTimeInterval(30 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(30 * 60)
            ),
            BloodGlucose(
                sgv: 100,
                date: Decimal(baseTime.timeIntervalSince1970 * 1000),
                dateString: baseTime
            )
        ]

        let profile = createBasicProfile()
        let basalProfile = createBasicBasalProfile()

        let result = try MealTotal.recentCarbs(
            treatments: treatments,
            pumpHistory: [],
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseData,
            time: testTime
        )

        #expect(result != nil)
        #expect(result!.carbs == 20)
        #expect(
            result!.currentDeviation!.isWithin(0.02, of: 0.67) == true,
            "currentDeviation: \(result!.currentDeviation!.description)"
        )
        #expect(result!.mealCOB.isWithin(0.25, of: 14) == true, "mealCOB: \(result!.mealCOB.description)")
    }

    @Test("should ignore treatments outside the meal window") func ignoreTreatmentsOutsideMealWindow() async throws {
        let baseTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        let treatmentTime = Date.from(isoString: "2016-06-19T06:00:00-04:00") // 6 hours before
        let testTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        let treatments = [
            MealInput(
                timestamp: treatmentTime,
                carbs: 20,
                bolus: nil
            )
        ]

        // Create glucose pattern with slight rise
        let glucoseData = [
            BloodGlucose(
                sgv: 110,
                date: Decimal(baseTime.addingTimeInterval(60 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(60 * 60)
            ),
            BloodGlucose(
                sgv: 105,
                date: Decimal(baseTime.addingTimeInterval(30 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(30 * 60)
            ),
            BloodGlucose(
                sgv: 100,
                date: Decimal(baseTime.timeIntervalSince1970 * 1000),
                dateString: baseTime
            )
        ]

        let profile = createBasicProfile()
        let basalProfile = createBasicBasalProfile()

        let result = try MealTotal.recentCarbs(
            treatments: treatments,
            pumpHistory: [],
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseData,
            time: testTime
        )

        #expect(result != nil)
        #expect(result?.carbs == 0)
        #expect(result?.mealCOB == 0)
        #expect(
            result?.currentDeviation!.isWithin(0.02, of: 0.67) == true,
            "currentDeviation: \(result!.currentDeviation!.description)"
        )
    }

    @Test("should respect maxMealAbsorptionTime from profile") func respectMaxMealAbsorptionTime() async throws {
        let baseTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        let treatmentTime = Date.from(isoString: "2016-06-19T10:00:00-04:00") // 2 hours before
        let testTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        let treatments = [
            MealInput(
                timestamp: treatmentTime,
                carbs: 20,
                bolus: nil
            )
        ]

        // Create glucose pattern with slight rise
        let glucoseData = [
            BloodGlucose(
                sgv: 110,
                date: Decimal(baseTime.addingTimeInterval(60 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(60 * 60)
            ),
            BloodGlucose(
                sgv: 105,
                date: Decimal(baseTime.addingTimeInterval(30 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(30 * 60)
            ),
            BloodGlucose(
                sgv: 100,
                date: Decimal(baseTime.timeIntervalSince1970 * 1000),
                dateString: baseTime
            )
        ]

        var profile = createBasicProfile()
        profile.maxMealAbsorptionTime = 2 // 2 hour window
        let basalProfile = createBasicBasalProfile()

        let result = try MealTotal.recentCarbs(
            treatments: treatments,
            pumpHistory: [],
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseData,
            time: testTime
        )

        #expect(result != nil)
        #expect(result?.carbs == 0)
        #expect(result?.mealCOB == 0)
    }

    @Test("should respect maxCOB from profile") func respectMaxCOB() async throws {
        let baseTime = Date.from(isoString: "2016-06-19T12:00:00-04:00")
        let testTime = Date.from(isoString: "2016-06-19T13:00:00-04:00")

        let treatments = [
            MealInput(
                timestamp: baseTime,
                carbs: 200,
                bolus: nil
            )
        ]

        // Create glucose pattern with slight rise
        let glucoseData = [
            BloodGlucose(
                sgv: 110,
                date: Decimal(baseTime.addingTimeInterval(60 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(60 * 60)
            ),
            BloodGlucose(
                sgv: 105,
                date: Decimal(baseTime.addingTimeInterval(30 * 60).timeIntervalSince1970 * 1000),
                dateString: baseTime.addingTimeInterval(30 * 60)
            ),
            BloodGlucose(
                sgv: 100,
                date: Decimal(baseTime.timeIntervalSince1970 * 1000),
                dateString: baseTime
            )
        ]

        let profile = createBasicProfile()
        let basalProfile = createBasicBasalProfile()

        let result = try MealTotal.recentCarbs(
            treatments: treatments,
            pumpHistory: [],
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseData,
            time: testTime
        )

        #expect(result != nil)
        #expect(result!.mealCOB <= 120)
    }
}
