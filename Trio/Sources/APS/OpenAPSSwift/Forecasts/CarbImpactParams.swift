import Foundation

struct CarbImpactParams {
    let cappedCarbImpact: Decimal
    let carbImpactDuration: Decimal
    let maxAbsorptionIntervals: Int
    let triangleIntervals: Int
    let remainingCarbImpactPeak: Decimal
    let remainingCarbAbsorptionTime: Decimal

    static func calculate(
        carbSensitivityFactor: Decimal,
        profile: Profile,
        mealData: ComputedCarbs,
        carbImpact: Decimal,
        sensitivityRatio: Decimal,
        currentTime: Date
    ) -> CarbImpactParams {
        let maxCarbAbsorptionRate: Decimal = 30 // g/h
        let maxCarbImpact = (maxCarbAbsorptionRate * carbSensitivityFactor * 5 / 60).jsRounded(scale: 1)
        let cappedCarbImpact = min(carbImpact, maxCarbImpact)

        let remainingCarbAbsorptionTime = ForecastGenerator.calculateRemainingCarbAbsorptionTime(
            sensitivityRatio: sensitivityRatio,
            maxMealAbsorptionTime: profile.maxMealAbsorptionTime,
            mealCOB: mealData.mealCOB,
            lastCarbTime: Date(timeIntervalSince1970: mealData.lastCarbTime / 1000),
            currentTime: currentTime
        )

        let carbImpactDuration: Decimal
        if carbImpact == 0 {
            carbImpactDuration = 0
        } else {
            // cid = Math.min(remainingCATime*60/5/2,Math.max(0, meal_data.mealCOB * csf / ci ));
            carbImpactDuration = min(
                remainingCarbAbsorptionTime * 60 / 5 / 2,
                max(0, mealData.mealCOB * carbSensitivityFactor / carbImpact)
            )
        }

        // Convert remainingCarbAbsorptionTime (hours) to intervals (each 5m):
        let dynamicAbsorptionIntervals = Int((remainingCarbAbsorptionTime * 60) / 5)
        // Number of 5-minute intervals over which we expect *all* carbs to absorb
        let maxAbsorptionIntervals = Int(profile.maxMealAbsorptionTime * Decimal(60) / 5)
        // Use smaller of both computed intervals, the dynamic and the max-clamped one as the actual # of decay triangle interval
        let triangleIntervals = min(dynamicAbsorptionIntervals, maxAbsorptionIntervals)

        // Total CI (mg/dL)
        let totalCarbImpact = max(0, cappedCarbImpact / 5 * 60 * remainingCarbAbsorptionTime / 2)
        // Total carbs absorbed from CI (g)
        let totalCarbsAbsorbed: Decimal = totalCarbImpact / carbSensitivityFactor

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
            remainingCarbImpactPeak = (remainingCarbs * carbSensitivityFactor * 5 / 60) / (remainingCarbAbsorptionTime / 2)
        } else {
            remainingCarbImpactPeak = 0
        }

        return CarbImpactParams(
            cappedCarbImpact: cappedCarbImpact,
            carbImpactDuration: carbImpactDuration,
            maxAbsorptionIntervals: maxAbsorptionIntervals,
            triangleIntervals: triangleIntervals,
            remainingCarbImpactPeak: remainingCarbImpactPeak,
            remainingCarbAbsorptionTime: remainingCarbAbsorptionTime
        )
    }
}
