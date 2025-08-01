import Foundation

/// The top-level orchestrator
enum ForecastGenerator {
    public static func generate(
        glucose: Decimal,
        glucoseStatus: GlucoseStatus,
        currentGlucoseImpact: Decimal,
        glucoseImpactSeries: [Decimal],
        glucoseImpactSeriesWithZeroTemp: [Decimal],
        iobData: [IobResult],
        mealData: ComputedCarbs,
        profile: Profile,
        preferences: Preferences,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        dynamicIsfResult: DynamicISFResult?,
        targetGlucose: Decimal,
        adjustedSensitivity: Decimal,
        sensitivityRatio: Decimal,
        naiveEventualGlucose _: Decimal,
        eventualGlucose: Decimal,
        threshold: Decimal,
        currentTime: Date
    ) -> ForecastResult {
        let profileCarbRatio = profile.carbRatio ?? profile.carbRatioFor(time: currentTime)
        let adjustedCarbRatio: Decimal
        if trioCustomOrefVariables.useOverride, trioCustomOrefVariables.cr {
            let overrideFactor = trioCustomOrefVariables.overridePercentage / 100
            adjustedCarbRatio = profileCarbRatio / overrideFactor
        } else {
            adjustedCarbRatio = profileCarbRatio
        }

        let carbSensitivityFactor = adjustedSensitivity / adjustedCarbRatio
        let minDelta = min(glucoseStatus.delta, glucoseStatus.shortAvgDelta)
        // this carbImpact is `ci` in JS
        var carbImpact = (minDelta - currentGlucoseImpact).jsRounded(scale: 1)
        let maxCarbAbsorptionRate = Decimal(30)
        let maxCI = (maxCarbAbsorptionRate * carbSensitivityFactor * Decimal(5) / Decimal(60)).jsRounded(scale: 1)
        if carbImpact > maxCI {
            carbImpact = maxCI
        }

        let carbImpactParams = CarbImpactParams.calculate(
            carbSensitivityFactor: carbSensitivityFactor,
            profile: profile,
            mealData: mealData,
            carbImpact: carbImpact,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )

        // this is `uci` in JS, it isn't limited by maxCI
        let uamCarbImpact = (minDelta - currentGlucoseImpact).jsRounded(scale: 1)

        // JS oref initializes all xxxPredBGs array with current glucose, we do the same, then generate
        let iobForecast = forecastIOB(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            iobData: iobData,
            carbImpact: carbImpact,
            dynamicIsfState: preferences.dynamicIsfState(),
            insulinFactor: dynamicIsfResult?.insulinFactor,
            tdd: trioCustomOrefVariables.tdd(profile: profile),
            adjustmentFactorLogrithmic: profile.adjustmentFactor
        )

        let cobForecast = forecastCOB(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            carbImpact: carbImpact,
            carbImpactParams: carbImpactParams
        )

        let uamForecast = forecastUAM(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            mealData: mealData,
            uamCarbImpact: uamCarbImpact,
            carbImpact: carbImpact,
            iobData: iobData,
            dynamicIsfState: preferences.dynamicIsfState(),
            insulinFactor: dynamicIsfResult?.insulinFactor,
            tdd: trioCustomOrefVariables.tdd(profile: profile),
            adjustmentFactorLogrithmic: profile.adjustmentFactor
        )

        let ztForecast = forecastZT(
            startingGlucose: glucose,
            glucoseImpactSeriesWithZeroTemp: glucoseImpactSeriesWithZeroTemp,
            targetBG: targetGlucose,
            iobData: iobData,
            dynamicIsfState: preferences.dynamicIsfState(),
            insulinFactor: dynamicIsfResult?.insulinFactor,
            tdd: trioCustomOrefVariables.tdd(profile: profile),
            adjustmentFactorLogrithmic: profile.adjustmentFactor
        )

        let computedForecastSelection = Self.computeForecastSelection(
            iob: iobForecast,
            cob: cobForecast,
            uam: uamForecast,
            zt: ztForecast,
            currentGlucose: glucose
        )

        let blendedForecasts = Self.blendForecasts(
            selectionResult: computedForecastSelection,
            carbs: mealData.carbs,
            mealCOB: mealData.mealCOB,
            enableUAM: profile.enableUAM,
            carbImpactDuration: carbImpactParams.carbImpactDuration,
            remainingCarbImpactPeak: carbImpactParams.remainingCarbImpactPeak,
            fractionCarbsLeft: mealData.carbs > 0 ? mealData.mealCOB / mealData.carbs : 0,
            threshold: threshold,
            targetGlucose: profile.targetBg ?? 100,
            currentGlucose: glucose
        )

        // FIXME: Revisit this after I get predBG working
        /*
         var eventualGlucose = eventualGlucose
         if let finalCOBGlucose = cobForecast.last {
             eventualGlucose = max(eventualGlucose, finalCOBGlucose)
         }
         if let finalUAMGlucose = uamForecast.last {
             eventualGlucose = max(eventualGlucose, finalUAMGlucose)
         }
          */

        return ForecastResult(
            iob: iobForecast,
            cob: cobForecast,
            uam: uamForecast,
            zt: ztForecast,
            eventualGlucose: eventualGlucose,
            minForecastedGlucose: blendedForecasts.minForecastedGlucose,
            minGuardGlucose: blendedForecasts.minGuardGlucose
        )
    }

    /// Calculates the dynamic remaining carb absorption time in hours, per oref0 logic.
    /// - Parameters:
    ///   - sensitivityRatio: ratio from autosens (usually 1.0 if not present)
    ///   - mealCOB: unabsorbed carbs (grams)
    ///   - lastCarbTime: timestamp of last carb entry (Date? or nil)
    ///   - currentTime: now
    /// - Returns: Remaining CA time in hours (Decimal)
    static func calculateRemainingCarbAbsorptionTime(
        sensitivityRatio: Decimal,
        maxMealAbsorptionTime _: Decimal,
        mealCOB: Decimal,
        lastCarbTime: Date?,
        currentTime: Date
    ) -> Decimal {
        var minRemainingCarbAbsorptionTime: Decimal = 3 // hours
        if sensitivityRatio > 0 {
            minRemainingCarbAbsorptionTime = minRemainingCarbAbsorptionTime / sensitivityRatio
        }

        var remainingCarbAbsorptionTime = minRemainingCarbAbsorptionTime
        if mealCOB > 0 {
            let assumedCarbAbsorptionRate: Decimal = 20 // g/h
            minRemainingCarbAbsorptionTime = max(minRemainingCarbAbsorptionTime, mealCOB / assumedCarbAbsorptionRate)
            if let lastCarbTime = lastCarbTime {
                let lastCarbAgeMin = Decimal(currentTime.timeIntervalSince(lastCarbTime) / 60).jsRounded()
                remainingCarbAbsorptionTime = minRemainingCarbAbsorptionTime + 1.5 * (lastCarbAgeMin / 60)
                remainingCarbAbsorptionTime = remainingCarbAbsorptionTime.jsRounded(scale: 1)
            }
        }

        return remainingCarbAbsorptionTime
    }

    static func computeForecastSelection(
        iob: [Decimal],
        cob: [Decimal],
        uam: [Decimal],
        zt: [Decimal],
        currentGlucose: Decimal
    ) -> ForecastSelectionResult {
        // In the JS, minPredBG is only considered after insulin peak, so use dropFirst
        let iobAfter90min = iob.dropFirst(18) // 90m at 5m intervals = 18
        let cobAfter90min = cob.dropFirst(18)
        let uamAfter60min = uam.dropFirst(12) // 60m at 5m intervals = 12

        let minIOBForecastGlucose = iobAfter90min.min() ?? Decimal(999)
        let minCOBForecastGlucose = cobAfter90min.min() ?? Decimal(999)
        let minUAMForecastGlucose = uamAfter60min.min() ?? Decimal(999)

        let minIOBGuardGlucose = iob.min() ?? Decimal(999)
        let minCOBGuardGlucose = cob.min() ?? Decimal(999)
        let minUAMGuardGlucose = uam.min() ?? Decimal(999)
        let minZTGuardGlucose = zt.min() ?? Decimal(999)

        let maxIOBForecastGlucose = iob.max() ?? currentGlucose
        let maxCOBForecastGlucose = cob.max() ?? currentGlucose
        let maxUAMForecastGlucose = uam.max() ?? currentGlucose

        let lastIOBForecastGlucose = iob.last ?? currentGlucose
        let lastCOBForecastGlucose = cob.last ?? currentGlucose
        let lastUAMForecastGlucose = uam.last ?? currentGlucose
        let lastZTForecastGlucose = zt.last ?? currentGlucose

        return ForecastSelectionResult(
            minIOBForecastGlucose: minIOBForecastGlucose,
            minCOBForecastGlucose: minCOBForecastGlucose,
            minUAMForecastGlucose: minUAMForecastGlucose,
            minIOBGuardGlucose: minIOBGuardGlucose,
            minCOBGuardGlucose: minCOBGuardGlucose,
            minUAMGuardGlucose: minUAMGuardGlucose,
            minZTGuardGlucose: minZTGuardGlucose,
            maxIOBForecastGlucose: maxIOBForecastGlucose,
            maxCOBForecastGlucose: maxCOBForecastGlucose,
            maxUAMForecastGlucose: maxUAMForecastGlucose,
            lastIOBForecastGlucose: lastIOBForecastGlucose,
            lastCOBForecastGlucose: lastCOBForecastGlucose,
            lastUAMForecastGlucose: lastUAMForecastGlucose,
            lastZTForecastGlucose: lastZTForecastGlucose
        )
    }

    /// Mirrors the oref0 JS logic for selecting/blending min/avg/guard BGs.
    static func blendForecasts(
        selectionResult: ForecastSelectionResult,
        carbs: Decimal,
        mealCOB _: Decimal,
        enableUAM: Bool,
        carbImpactDuration: Decimal,
        remainingCarbImpactPeak: Decimal,
        fractionCarbsLeft: Decimal,
        threshold: Decimal,
        targetGlucose: Decimal,
        currentGlucose: Decimal
    ) -> ForecastBlendingResult {
        // 1. Calculate minZTUAMForecastGlucose ("minZTUAMPredBG" in JS)
        var minZTUAMForecastGlucose = selectionResult.minUAMForecastGlucose
        if selectionResult.minZTGuardGlucose < threshold {
            minZTUAMForecastGlucose = ((selectionResult.minUAMForecastGlucose + selectionResult.minZTGuardGlucose) / 2)
                .rounded()
        } else if selectionResult.minZTGuardGlucose < targetGlucose {
            let blendPct = (selectionResult.minZTGuardGlucose - threshold) / (targetGlucose - threshold)
            let blendedMinZTGuardGlucose = selectionResult.minUAMForecastGlucose * blendPct + selectionResult
                .minZTGuardGlucose * (1 - blendPct)
            minZTUAMForecastGlucose = ((selectionResult.minUAMForecastGlucose + blendedMinZTGuardGlucose) / 2).rounded()
        } else if selectionResult.minZTGuardGlucose > selectionResult.minUAMForecastGlucose {
            minZTUAMForecastGlucose = ((selectionResult.minUAMForecastGlucose + selectionResult.minZTGuardGlucose) / 2)
                .rounded()
        }

        // 2. avgForecastGlucose blending (like avgPredBG)
        let avgForecastGlucose: Decimal
        if selectionResult.minUAMForecastGlucose < 999, selectionResult.minCOBForecastGlucose < 999 {
            avgForecastGlucose = (
                (1 - fractionCarbsLeft) * selectionResult
                    .lastUAMForecastGlucose + fractionCarbsLeft * selectionResult.lastCOBForecastGlucose
            ).rounded()
        } else if selectionResult.minCOBForecastGlucose < 999 {
            avgForecastGlucose = ((selectionResult.lastIOBForecastGlucose + selectionResult.lastCOBForecastGlucose) / 2)
                .rounded()
        } else if selectionResult.minUAMForecastGlucose < 999 {
            avgForecastGlucose = ((selectionResult.lastIOBForecastGlucose + selectionResult.lastUAMForecastGlucose) / 2)
                .rounded()
        } else {
            avgForecastGlucose = selectionResult.lastIOBForecastGlucose.rounded()
        }
        let adjustedAvgForecastGlucose = max(avgForecastGlucose, selectionResult.minZTGuardGlucose)

        // 3. minGuardGlucose
        let minGuardGlucose: Decimal
        if carbImpactDuration > 0 || remainingCarbImpactPeak > 0 {
            if enableUAM {
                minGuardGlucose = (
                    fractionCarbsLeft * selectionResult
                        .minCOBGuardGlucose + (1 - fractionCarbsLeft) * selectionResult.minUAMGuardGlucose
                ).rounded()
            } else {
                minGuardGlucose = selectionResult.minCOBGuardGlucose.rounded()
            }
        } else if enableUAM {
            minGuardGlucose = selectionResult.minUAMGuardGlucose.rounded()
        } else {
            minGuardGlucose = selectionResult.minIOBGuardGlucose.rounded()
        }

        // 4. minForecastedGlucose ("minPredBG")
        var minForecastedGlucose: Decimal = selectionResult.minIOBForecastGlucose.rounded()
        if carbs > 0 {
            if !enableUAM, selectionResult.minCOBForecastGlucose < 999 {
                minForecastedGlucose = max(selectionResult.minIOBForecastGlucose, selectionResult.minCOBForecastGlucose)
            } else if selectionResult.minCOBForecastGlucose < 999 {
                let blendedMinForecastGlucose = fractionCarbsLeft * selectionResult
                    .minCOBForecastGlucose + (1 - fractionCarbsLeft) * minZTUAMForecastGlucose
                minForecastedGlucose = max(
                    selectionResult.minIOBForecastGlucose,
                    selectionResult.minCOBForecastGlucose,
                    blendedMinForecastGlucose
                ).rounded()
            } else if enableUAM {
                minForecastedGlucose = minZTUAMForecastGlucose
            } else {
                minForecastedGlucose = minGuardGlucose
            }
        } else if enableUAM {
            minForecastedGlucose = max(selectionResult.minIOBForecastGlucose, minZTUAMForecastGlucose).rounded()
        }

        // Clamp minForecastedGlucose to not exceed adjustedAvgForecastGlucose
        minForecastedGlucose = min(minForecastedGlucose, adjustedAvgForecastGlucose)

        // JS: If maxCOBPredBG > bg, don't trust UAM too much
        if selectionResult.maxCOBForecastGlucose > currentGlucose {
            minForecastedGlucose = min(minForecastedGlucose, selectionResult.maxCOBForecastGlucose)
        }

        return ForecastBlendingResult(
            minForecastedGlucose: minForecastedGlucose,
            avgForecastedGlucose: adjustedAvgForecastGlucose,
            minGuardGlucose: minGuardGlucose
        )
    }

    /// Trims trailing flat-line points beyond a “lookback” count
    public static func trimFlatTails(_ series: [Decimal], lookback: Int) -> [Decimal] {
        guard series.count > lookback, lookback >= 0 else {
            return series
        }
        let maxToRemove = series.count - lookback
        let reversedSeries = series.map({ $0.jsRounded() }).reversed()
        var removeCount = 0
        for (curr, next) in zip(reversedSeries, reversedSeries.dropFirst()) {
            guard curr == next else {
                break
            }
            removeCount += 1
        }

        removeCount = min(maxToRemove, removeCount)

        return Array(series.dropLast(removeCount))
    }

    /// Trims trailing ZT points once they are rising and above target
    public static func trimZTTails(series: [Decimal], targetBG: Decimal) -> [Decimal] {
        let lookback = 7 // i > 6 in JS

        guard series.count > lookback else {
            return series
        }
        let maxToRemove = series.count - lookback
        let reversedSeries = series.map({ $0.jsRounded() }).reversed()
        var removeCount = 0
        for (curr, next) in zip(reversedSeries, reversedSeries.dropFirst()) {
            if next >= curr || curr <= targetBG {
                break
            }
            removeCount += 1
        }

        removeCount = min(maxToRemove, removeCount)

        return Array(series.dropLast(removeCount))
    }
}
