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
        if trioCustomOrefVariables.useOverride, trioCustomOrefVariables.cr || trioCustomOrefVariables.isfAndCr {
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
        let iobResult = forecastIOB(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            iobData: iobData,
            carbImpact: carbImpact,
            dynamicIsfState: preferences.dynamicIsfState(profile: profile, trioCustomOrefVariables: trioCustomOrefVariables),
            insulinFactor: dynamicIsfResult?.insulinFactor,
            tdd: trioCustomOrefVariables.tdd(profile: profile),
            adjustmentFactorLogrithmic: profile.adjustmentFactor
        )

        let cobResult = forecastCOB(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            carbImpact: carbImpact,
            carbImpactParams: carbImpactParams
        )

        let uamResult = forecastUAM(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            mealData: mealData,
            uamCarbImpact: uamCarbImpact,
            carbImpact: carbImpact,
            iobData: iobData,
            dynamicIsfState: preferences.dynamicIsfState(profile: profile, trioCustomOrefVariables: trioCustomOrefVariables),
            insulinFactor: dynamicIsfResult?.insulinFactor,
            tdd: trioCustomOrefVariables.tdd(profile: profile),
            adjustmentFactorLogrithmic: profile.adjustmentFactor
        )

        let ztResult = forecastZT(
            startingGlucose: glucose,
            glucoseImpactSeriesWithZeroTemp: glucoseImpactSeriesWithZeroTemp,
            targetBG: targetGlucose,
            iobData: iobData,
            dynamicIsfState: preferences.dynamicIsfState(profile: profile, trioCustomOrefVariables: trioCustomOrefVariables),
            insulinFactor: dynamicIsfResult?.insulinFactor,
            tdd: trioCustomOrefVariables.tdd(profile: profile),
            adjustmentFactorLogrithmic: profile.adjustmentFactor
        )

        let initialForecasts = calculateMinMaxForecastedGlucose(
            currentGlucose: glucose,
            iobForecast: iobResult,
            cobForecast: cobResult,
            uamForecast: uamResult,
            ztForecast: ztResult,
            carbImpactDuration: carbImpactParams.carbImpactDuration,
            remainingCarbImpactPeak: carbImpactParams.remainingCarbImpactPeak,
            uamEnabled: profile.enableUAM
        )

        let blendedForecasts = Self.blendForecasts(
            iobResult: initialForecasts.iob,
            cobResult: initialForecasts.cob,
            uamResult: initialForecasts.uam,
            ztResult: initialForecasts.zt,
            carbs: mealData.carbs,
            mealCOB: mealData.mealCOB,
            enableUAM: profile.enableUAM,
            carbImpactDuration: carbImpactParams.carbImpactDuration,
            remainingCarbImpactPeak: carbImpactParams.remainingCarbImpactPeak,
            fractionCarbsLeft: mealData.carbs > 0 ? mealData.mealCOB / mealData.carbs : Decimal(0),
            threshold: threshold,
            targetGlucose: targetGlucose,
            currentGlucose: glucose
        )

        var eventualGlucose = eventualGlucose
        var finalCobForecast: [Decimal]?
        if mealData.mealCOB > 0, carbImpact > 0 || carbImpactParams.remainingCarbImpactPeak > 0 {
            finalCobForecast = cobResult.forecasts
            if let lastCobGlucose = cobResult.forecasts.last {
                eventualGlucose = max(eventualGlucose, lastCobGlucose.jsRounded())
            }
        }

        var finalUamForecast: [Decimal]?
        if profile.enableUAM, carbImpact > 0 || carbImpactParams.remainingCarbImpactPeak > 0 {
            finalUamForecast = uamResult.forecasts
            if let lastUamGlucose = uamResult.forecasts.last {
                eventualGlucose = max(eventualGlucose, lastUamGlucose.jsRounded())
            }
        }

        return ForecastResult(
            iob: iobResult.forecasts,
            cob: finalCobForecast,
            uam: finalUamForecast,
            zt: ztResult.forecasts,
            internalCob: cobResult.forecasts,
            internalUam: uamResult.forecasts,
            eventualGlucose: eventualGlucose,
            minForecastedGlucose: blendedForecasts.minForecastedGlucose,
            minIOBForecastedGlucose: initialForecasts.iob.minForecastGlucose,
            minGuardGlucose: blendedForecasts.minGuardGlucose,
            carbImpact: carbImpact,
            remainingCarbImpactPeak: carbImpactParams.remainingCarbImpactPeak,
            adjustedCarbRatio: adjustedCarbRatio
        )
    }

    /// This function does the min/max glucose forecasts at the end of the main forecast loop
    /// in JS. It operates on raw forecasts and there is a cross dependency between IOB
    /// predictions and the UAM predictions, so we need to pull out this logic here
    static func calculateMinMaxForecastedGlucose(
        currentGlucose: Decimal,
        iobForecast: IndividualForecast,
        cobForecast: IndividualForecast,
        uamForecast: IndividualForecast,
        ztForecast: IndividualForecast,
        carbImpactDuration: Decimal,
        remainingCarbImpactPeak: Decimal,
        uamEnabled: Bool
    ) -> AllForecasts {
        // FIXME: we need to make sure that these will all be the same length
        // but since they're running their loops on the same data they should be
        let minCount = min(
            iobForecast.rawForecasts.count,
            cobForecast.rawForecasts.count,
            uamForecast.rawForecasts.count
        )

        var maxIobForecastGlucose = currentGlucose
        var maxCobForecastGlucose = currentGlucose
        var maxUamForecastGlucose = currentGlucose
        var minIobForecastGlucose = Decimal(999)
        var minCobForecastGlucose = Decimal(999)
        var minUamForecastGlucose = Decimal(999)

        let insulinPeak5m = 18

        // start at 1 because the first entry is currentGlucose
        for index in 1 ..< minCount {
            let length = index + 1
            let currentIobForecastGlucose = iobForecast.rawForecasts[index]
            let currentCobForecastGlucose = cobForecast.rawForecasts[index]
            let currentUamForecastGlucose = uamForecast.rawForecasts[index]

            // the max calculations don't get rounded in JS
            if length > insulinPeak5m, currentIobForecastGlucose < minIobForecastGlucose {
                minIobForecastGlucose = currentIobForecastGlucose.jsRounded()
            }
            if currentIobForecastGlucose > maxIobForecastGlucose {
                maxIobForecastGlucose = currentIobForecastGlucose
            }
            if carbImpactDuration != 0 || remainingCarbImpactPeak > 0, length > insulinPeak5m,
               currentCobForecastGlucose < minCobForecastGlucose
            {
                minCobForecastGlucose = currentCobForecastGlucose.jsRounded()
            }
            // BUG: I can't tell if the comparison against maxIobForecastGlucose is
            // intentional or not, but this is what is in JS
            if carbImpactDuration != 0 || remainingCarbImpactPeak > 0, currentCobForecastGlucose > maxIobForecastGlucose {
                maxCobForecastGlucose = currentCobForecastGlucose
            }
            if uamEnabled, length > 12, currentUamForecastGlucose < minUamForecastGlucose {
                minUamForecastGlucose = currentUamForecastGlucose.jsRounded()
            }
            // BUG: I can't tell if the comparison against maxIobForecastGlucose is
            // intentional or not, but this is what is in JS
            if uamEnabled, currentUamForecastGlucose > maxIobForecastGlucose {
                maxUamForecastGlucose = currentUamForecastGlucose
            }
        }

        minIobForecastGlucose = max(39, minIobForecastGlucose)
        minCobForecastGlucose = max(39, minCobForecastGlucose)
        minUamForecastGlucose = max(39, minUamForecastGlucose)

        return AllForecasts(
            iob: IOBForecast(
                forecasts: iobForecast.forecasts,
                minGuardGlucose: iobForecast.minGuardGlucose,
                minForecastGlucose: minIobForecastGlucose,
                maxForecastGlucose: maxIobForecastGlucose,
                lastForecastGlucose: iobForecast.rawForecasts.last ?? currentGlucose
            ),
            zt: ZTForecast(
                forecasts: ztForecast.forecasts,
                minGuardGlucose: ztForecast.minGuardGlucose
            ),
            cob: COBForecast(
                forecasts: cobForecast.forecasts,
                minGuardGlucose: cobForecast.minGuardGlucose,
                minForecastGlucose: minCobForecastGlucose,
                maxForecastGlucose: maxCobForecastGlucose,
                lastForecastGlucose: cobForecast.rawForecasts.last ?? currentGlucose
            ),
            uam: UAMForecast(
                forecasts: uamForecast.forecasts,
                minGuardGlucose: uamForecast.minGuardGlucose,
                minForecastGlucose: minUamForecastGlucose,
                maxForecastGlucose: maxUamForecastGlucose,
                duration: uamForecast.duration!,
                lastForecastGlucose: uamForecast.rawForecasts.last ?? currentGlucose
            ) // I don't love the force unwrap here but it should always be set
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
                remainingCarbAbsorptionTime = minRemainingCarbAbsorptionTime + (1.5 * lastCarbAgeMin) / 60
                remainingCarbAbsorptionTime = remainingCarbAbsorptionTime.jsRounded(scale: 1)
            }
        }

        return remainingCarbAbsorptionTime
    }

    /// Mirrors the oref0 JS logic for selecting/blending min/avg/guard BGs.
    static func blendForecasts(
        iobResult: IOBForecast,
        cobResult: COBForecast,
        uamResult: UAMForecast,
        ztResult: ZTForecast,
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
        var minZTUAMForecastGlucose = uamResult.minForecastGlucose
        if ztResult.minGuardGlucose < threshold {
            minZTUAMForecastGlucose = (uamResult.minForecastGlucose + ztResult.minGuardGlucose) / 2
        } else if ztResult.minGuardGlucose < targetGlucose {
            let blendPct = (ztResult.minGuardGlucose - threshold) / (targetGlucose - threshold)
            let blendedMinZTGuardGlucose = uamResult.minForecastGlucose * blendPct + ztResult.minGuardGlucose * (1 - blendPct)
            minZTUAMForecastGlucose = (uamResult.minForecastGlucose + blendedMinZTGuardGlucose) / 2
        } else if ztResult.minGuardGlucose > uamResult.minForecastGlucose {
            minZTUAMForecastGlucose = (uamResult.minForecastGlucose + ztResult.minGuardGlucose) / 2
        }
        minZTUAMForecastGlucose = minZTUAMForecastGlucose.jsRounded()

        // 2. avgForecastGlucose blending (like avgPredBG)
        let avgerageForecastGlucose: Decimal
        if uamResult.minForecastGlucose < 999, cobResult.minForecastGlucose < 999 {
            avgerageForecastGlucose = (
                (1 - fractionCarbsLeft) * uamResult.lastForecastGlucose + fractionCarbsLeft * cobResult.lastForecastGlucose
            ).jsRounded()
        } else if cobResult.minForecastGlucose < 999 {
            avgerageForecastGlucose =
                ((iobResult.lastForecastGlucose + cobResult.lastForecastGlucose) / 2)
                    .jsRounded()
        } else if uamResult.minForecastGlucose < 999 {
            avgerageForecastGlucose =
                ((iobResult.lastForecastGlucose + uamResult.lastForecastGlucose) / 2)
                    .jsRounded()
        } else {
            avgerageForecastGlucose = iobResult.lastForecastGlucose.jsRounded()
        }
        let adjustedAverageForecastGlucose = max(avgerageForecastGlucose, ztResult.minGuardGlucose)

        // 3. minGuardGlucose
        let minGuardGlucose: Decimal
        if carbImpactDuration > 0 || remainingCarbImpactPeak > 0 {
            if enableUAM {
                minGuardGlucose = (
                    fractionCarbsLeft * cobResult.minGuardGlucose + (1 - fractionCarbsLeft) * uamResult.minGuardGlucose
                ).jsRounded()
            } else {
                minGuardGlucose = cobResult.minGuardGlucose.jsRounded()
            }
        } else if enableUAM {
            minGuardGlucose = uamResult.minGuardGlucose.jsRounded()
        } else {
            minGuardGlucose = iobResult.minGuardGlucose.jsRounded()
        }

        // 4. minForecastedGlucose ("minPredBG")
        var minForecastedGlucose: Decimal = iobResult.minForecastGlucose.jsRounded()
        if carbs > 0 {
            if !enableUAM, cobResult.minForecastGlucose < 999 {
                minForecastedGlucose = max(iobResult.minForecastGlucose, cobResult.minForecastGlucose)
            } else if cobResult.minForecastGlucose < 999 {
                let blendedMinForecastGlucose = fractionCarbsLeft * cobResult
                    .minForecastGlucose + (1 - fractionCarbsLeft) * minZTUAMForecastGlucose
                minForecastedGlucose = max(
                    iobResult.minForecastGlucose,
                    cobResult.minForecastGlucose,
                    blendedMinForecastGlucose
                ).jsRounded()
            } else if enableUAM {
                minForecastedGlucose = minZTUAMForecastGlucose
            } else {
                minForecastedGlucose = minGuardGlucose
            }
        } else if enableUAM {
            minForecastedGlucose = max(iobResult.minForecastGlucose, minZTUAMForecastGlucose).jsRounded()
        }

        // Clamp minForecastedGlucose to not exceed adjustedAvgForecastGlucose
        minForecastedGlucose = min(minForecastedGlucose, adjustedAverageForecastGlucose)

        // JS: If maxCOBPredBG > bg, don't trust UAM too much
        if cobResult.maxForecastGlucose > currentGlucose {
            minForecastedGlucose = min(minForecastedGlucose, cobResult.maxForecastGlucose)
        }

        return ForecastBlendingResult(
            minForecastedGlucose: minForecastedGlucose,
            avgForecastedGlucose: adjustedAverageForecastGlucose,
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
