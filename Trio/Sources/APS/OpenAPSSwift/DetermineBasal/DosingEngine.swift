import Foundation

enum DosingEngine {
    struct DosingInputs {
        let reason: String
        let carbsRequired: (carbs: Decimal, minutes: Decimal)?
    }

    static func prepareDosingInputs(
        profile: Profile,
        mealData: ComputedCarbs,
        forecast: ForecastResult,
        naiveEventualGlucose: Decimal,
        threshold: Decimal,
        glucoseImpact: Decimal,
        deviation: Decimal,
        currentBasal: Decimal,
        overrideFactor: Decimal,
        adjustedSensitivity: Decimal,
        isfReason: String,
        tddReason: String,
        targetLog: String // This is a pre-formatted string from the JS
    ) -> DosingInputs {
        let lastIOBpredBG = forecast.iob.last ?? 0
        let lastCOBpredBG = forecast.cob?.last
        let lastUAMpredBG = forecast.uam?.last

        var reason =
            "\(isfReason), COB: \(mealData.mealCOB), Dev: \(deviation), BGI: \(glucoseImpact), CR: \(forecast.adjustedCarbRatio), Target: \(targetLog), minPredBG \(forecast.minForecastedGlucose), minGuardBG \(forecast.minGuardGlucose), IOBpredBG \(lastIOBpredBG)"

        if let lastCOB = lastCOBpredBG {
            reason += ", COBpredBG \(lastCOB)"
        }
        if let lastUAM = lastUAMpredBG {
            reason += ", UAMpredBG \(lastUAM)"
        }
        reason += tddReason
        reason += "; " // Start of conclusion

        let carbsRequiredResult = calculateCarbsRequired(
            profile: profile,
            mealData: mealData,
            naiveEventualGlucose: naiveEventualGlucose,
            minGuardGlucose: forecast.minGuardGlucose,
            threshold: threshold,
            iobForecast: forecast.iob,
            cobForecast: forecast.internalCob,
            carbImpact: forecast.carbImpact,
            remainingCarbImpactPeak: forecast.remainingCarbImpactPeak,
            currentBasal: currentBasal,
            overrideFactor: overrideFactor,
            adjustedSensitivity: adjustedSensitivity,
            adjustedCarbRatio: forecast.adjustedCarbRatio
        )

        if let result = carbsRequiredResult {
            reason += "\(result.carbs) add'l carbs req w/in \(result.minutes)m; "
        }

        return DosingInputs(reason: reason, carbsRequired: carbsRequiredResult)
    }

    /// Calculates the carbohydrates required to avoid a potential hypoglycemic event.
    ///
    /// - Returns: A tuple containing the required carbs and minutes until BG is below threshold, or `nil` if no carbs are required.
    static func calculateCarbsRequired(
        profile: Profile,
        mealData: ComputedCarbs,
        naiveEventualGlucose: Decimal,
        minGuardGlucose: Decimal,
        threshold: Decimal,
        iobForecast: [Decimal],
        cobForecast: [Decimal],
        carbImpact: Decimal,
        remainingCarbImpactPeak: Decimal,
        currentBasal: Decimal,
        overrideFactor: Decimal,
        adjustedSensitivity: Decimal,
        adjustedCarbRatio: Decimal
    ) -> (carbs: Decimal, minutes: Decimal)? {
        var carbsRequiredGlucose = naiveEventualGlucose
        if naiveEventualGlucose < 40 {
            carbsRequiredGlucose = min(minGuardGlucose, naiveEventualGlucose)
        }

        let glucoseUndershoot = threshold - carbsRequiredGlucose

        var minutesAboveThreshold = Decimal(240)

        let useCOBForecast = mealData.mealCOB > 0 && (carbImpact > 0 || remainingCarbImpactPeak > 0)
        let forecast = useCOBForecast ? cobForecast : iobForecast

        // At this point in the JS the forecasts have already been rounded
        for (index, glucose) in forecast.map({ $0.jsRounded() }).enumerated() {
            if glucose < threshold {
                minutesAboveThreshold = Decimal(5) * Decimal(index)
                break
            }
        }

        let zeroTempDuration = minutesAboveThreshold
        let zeroTempEffect = currentBasal * adjustedSensitivity * overrideFactor * zeroTempDuration / 60

        let mealCarbs = mealData.carbs
        let cobForCarbsRequired = max(0, mealData.mealCOB - (Decimal(0.25) * mealCarbs))

        guard adjustedCarbRatio > 0 else { return nil }
        let carbSensitivityFactor = adjustedSensitivity / adjustedCarbRatio
        guard carbSensitivityFactor > 0 else { return nil }

        var carbsRequired = (glucoseUndershoot - zeroTempEffect) / carbSensitivityFactor - cobForCarbsRequired
        carbsRequired = carbsRequired.rounded(toPlaces: 0)

        let carbsRequiredThreshold = profile.carbsReqThreshold
        if carbsRequired >= carbsRequiredThreshold, minutesAboveThreshold <= 45 {
            return (carbs: carbsRequired, minutes: minutesAboveThreshold)
        }

        return nil
    }
}
