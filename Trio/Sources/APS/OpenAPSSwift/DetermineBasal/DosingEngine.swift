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
        bgi: Decimal,
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
            "\(isfReason), COB: \(mealData.mealCOB), Dev: \(deviation), BGI: \(bgi), CR: \(forecast.adjustedCarbRatio), Target: \(targetLog), minPredBG \(forecast.minForecastedGlucose), minGuardBG \(forecast.minGuardGlucose), IOBpredBG \(lastIOBpredBG)"

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
            iobPrediction: forecast.iob,
            cobPrediction: forecast.internalCob,
            ci: forecast.carbImpact,
            remainingCIpeak: forecast.remainingCarbImpactPeak,
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
        iobPrediction: [Decimal],
        cobPrediction: [Decimal],
        ci: Decimal,
        remainingCIpeak: Decimal,
        currentBasal: Decimal,
        overrideFactor: Decimal,
        adjustedSensitivity: Decimal,
        adjustedCarbRatio: Decimal
    ) -> (carbs: Decimal, minutes: Decimal)? {
        var carbsReqBG = naiveEventualGlucose
        if naiveEventualGlucose < 40 {
            carbsReqBG = min(minGuardGlucose, naiveEventualGlucose)
        }

        let bgUndershoot = threshold - carbsReqBG

        var minutesAboveThreshold = Decimal(240)

        let useCOBprediction = mealData.mealCOB > 0 && (ci > 0 || remainingCIpeak > 0)
        let prediction = useCOBprediction ? cobPrediction : iobPrediction

        // At this point in the JS the forecasts have already been rounded
        for (index, glucose) in prediction.map({ $0.jsRounded() }).enumerated() {
            if glucose < threshold {
                minutesAboveThreshold = Decimal(5) * Decimal(index)
                break
            }
        }

        let zeroTempDuration = minutesAboveThreshold
        let zeroTempEffect = currentBasal * adjustedSensitivity * overrideFactor * zeroTempDuration / 60

        let mealCarbs = mealData.carbs
        let cobForCarbsReq = max(0, mealData.mealCOB - (Decimal(0.25) * mealCarbs))

        guard adjustedCarbRatio > 0 else { return nil }
        let csf = adjustedSensitivity / adjustedCarbRatio
        guard csf > 0 else { return nil }

        var carbsReq = (bgUndershoot - zeroTempEffect) / csf - cobForCarbsReq
        carbsReq = carbsReq.rounded(toPlaces: 0)

        let carbsReqThreshold = profile.carbsReqThreshold
        if carbsReq >= carbsReqThreshold, minutesAboveThreshold <= 45 {
            return (carbs: carbsReq, minutes: minutesAboveThreshold)
        }

        return nil
    }
}
