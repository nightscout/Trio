import Foundation

enum MealGeneratorError {
    static func generate(
        pumpHistory: [PumpHistoryEvent],
        profile: Profile,
        basalProfile: [BasalProfileEntry],
        clock: Date,
        carbHistory: [CarbsEntry],
        glucoseHistory: [BloodGlucose]
    ) -> ComputedCarbs? {
        var treatments: [MealInput] = MealHistory.findMealInputs(pumpHistory: pumpHistory, carbHistory: carbHistory)
        
        // TODO: do we need to handle the clock timezone handling? We'll parse in a proper Swift Date anyhow
        
        return MealTotal.recentCarbs(treatments: treatments, pumpHistory: pumpHistory, profile: profile, basalProfile: basalProfile, glucose: glucoseHistory, time: clock)
    }
}
