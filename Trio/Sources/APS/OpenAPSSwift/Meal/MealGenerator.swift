import Foundation

enum MealGenerator {
    static func generate(
        pumpHistory: [PumpHistoryEvent],
        profile: Profile,
        basalProfile: [BasalProfileEntry],
        clock: Date,
        carbHistory: [CarbsEntry],
        glucoseHistory: [BloodGlucose]
    ) throws -> ComputedCarbs? {
        let treatments: [MealInput] = MealHistory.findMealInputs(pumpHistory: pumpHistory, carbHistory: carbHistory)

        let recentCarbs = try MealTotal.recentCarbs(
            treatments: treatments,
            pumpHistory: pumpHistory,
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseHistory,
            time: clock
        )

        // copy the glucose check from prepare/meal.js in Trio
        guard glucoseHistory.count >= 4 else {
            return ComputedCarbs(
                carbs: 0,
                mealCOB: 0,
                currentDeviation: 0,
                maxDeviation: 0,
                minDeviation: 0,
                slopeFromMaxDeviation: 0,
                slopeFromMinDeviation: 0,
                allDeviations: [],
                lastCarbTime: 0
            )
        }

        return recentCarbs
    }
}
