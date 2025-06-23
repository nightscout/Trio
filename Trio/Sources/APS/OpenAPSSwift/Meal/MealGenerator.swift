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

        return try MealTotal.recentCarbs(
            treatments: treatments,
            pumpHistory: pumpHistory,
            profile: profile,
            basalProfile: basalProfile,
            glucose: glucoseHistory,
            time: clock
        )
    }
}
