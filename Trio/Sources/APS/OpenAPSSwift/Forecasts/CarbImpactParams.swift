import Foundation

struct CarbImpactParams {
    let carbSensivityFactor: Decimal
    let cappedCarbImpact: Decimal
    let remainingCarbAbsorptionTime: Decimal
    let maxAbsorptionIntervals: Int
    let triangleIntervals: Int
    let remainingCarbImpactPeak: Decimal

    static func calculate(
        adjustedSensitivity: Decimal,
        profile: Profile,
        mealData: ComputedCarbs,
        carbImpact: Decimal,
        sensitivityRatio: Decimal,
        currentTime: Date
    ) -> CarbImpactParams {
        let carbSensivityFactor = adjustedSensitivity / (profile.carbRatio ?? profile.carbRatioFor(time: currentTime))
        
        // Initial carb impact in mg/dL per 5m
        let initialCarbImpact = carbImpact * carbSensivityFactor
        let maxCarbAbsorptionRate: Decimal = 30 // g/h
        let maxCarbImpact = (maxCarbAbsorptionRate * carbSensivityFactor * 5 / 60).rounded(toPlaces: 1)
        let cappedCarbImpact = min(initialCarbImpact, maxCarbImpact)

        let computedRemainingCarbAbsorptionTime = ForecastGenerator.calculateRemainingCarbAbsorptionTime(
            sensitivityRatio: sensitivityRatio,
            maxMealAbsorptionTime: profile.maxMealAbsorptionTime,
            mealCOB: mealData.mealCOB,
            lastCarbTime: Date(timeIntervalSince1970: mealData.lastCarbTime),
            currentTime: currentTime
        )
        // Clamp remainingTime for more robustness
        let remainingCarbAbsorptionTime = min(computedRemainingCarbAbsorptionTime, profile.maxMealAbsorptionTime)

        // Convert remainingCarbAbsorptionTime (hours) to intervals (each 5m):
        let dynamicAbsorptionIntervals = Int((remainingCarbAbsorptionTime * 60) / 5)
        // Number of 5-minute intervals over which we expect *all* carbs to absorb
        let maxAbsorptionIntervals = Int(profile.maxMealAbsorptionTime * Decimal(60) / 5)
        // Use smaller of both computed intervals, the dynamic and the max-clamped one as the actual # of decay triangle interval
        let triangleIntervals = min(dynamicAbsorptionIntervals, maxAbsorptionIntervals)

        // Total CI (mg/dL)
        let totalCarbImpact = max(0, cappedCarbImpact / 5 * 60 * remainingCarbAbsorptionTime / 2)
        // Total carbs absorbed from CI (g)
        let totalCarbsAbsorbed: Decimal = totalCarbImpact / carbSensivityFactor

        // Remaining carbs cap/fraction logic
        let remainingCarbsCap = min(90, profile.remainingCarbsCap)
        let remainingCarbsFraction = min(1, profile.remainingCarbsFraction)
        let remainingCarbsIgnore = 1 - remainingCarbsFraction

        var remainingCarbs = max(0, mealData.mealCOB - totalCarbsAbsorbed - mealData.carbs * remainingCarbsIgnore)
        remainingCarbs = min(remainingCarbsCap, remainingCarbs)

        // /\ triangle for remaining carbs
        // Peak impact (mg/dL per 5m) of the *remaining* carbs
        let remainingCarbImpactPeak: Decimal
        if remainingCarbAbsorptionTime > 0 {
            remainingCarbImpactPeak = (remainingCarbs * carbSensivityFactor * 5 / 60) / (remainingCarbAbsorptionTime / 2)
        } else {
            remainingCarbImpactPeak = 0
        }

        return CarbImpactParams(
            carbSensivityFactor: carbSensivityFactor,
            cappedCarbImpact: cappedCarbImpact,
            remainingCarbAbsorptionTime: remainingCarbAbsorptionTime,
            maxAbsorptionIntervals: maxAbsorptionIntervals,
            triangleIntervals: triangleIntervals,
            remainingCarbImpactPeak: remainingCarbImpactPeak
        )
    }
}
