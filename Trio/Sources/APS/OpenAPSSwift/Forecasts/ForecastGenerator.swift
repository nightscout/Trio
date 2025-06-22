import Foundation

/// The top-level orchestrator
struct ForecastGenerator {
    let iob: SingleForecasting
    let cob: SingleForecasting
    let uam: SingleForecasting
    let zt: SingleForecasting

    init(
        iob: SingleForecasting = IOBForecastGenerator(),
        cob: SingleForecasting = COBForecastGenerator(),
        uam: SingleForecasting = UAMForecastGenerator(),
        zt: SingleForecasting = ZTForecastGenerator()
    ) {
        self.iob = iob
        self.cob = cob
        self.uam = uam
        self.zt = zt
    }

    public func generate(
        glucose: Decimal,
        glucoseImpactSeries: [Decimal],
        iobData _: [IobResult],
        mealData: ComputedCarbs,
        profile: Profile,
        adjustedSensitivity: Decimal,
        sensitivityRatio: Decimal,
        naiveEventualGlucose _: Decimal,
        eventualGlucose: Decimal,
        threshold: Decimal,
        currentTime: Date
    ) -> ForecastResult {
        let carbImpact = mealData
            .currentDeviation * (profile.carbRatio ?? profile.carbRatioFor(time: currentTime)) /
            (profile.sens ?? profile.sensitivityFor(time: currentTime))
        let deviation = mealData.currentDeviation

        // JS oref initializes all xxxPredBGs array with current glucose, we do the same, then generate
        let iobForecast = [glucose] + iob.forecast(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            mealData: mealData,
            profile: profile,
            carbImpact: carbImpact,
            deviation: deviation,
            adjustedSensitivity: adjustedSensitivity,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )

        let cobForecast = [glucose] + cob.forecast(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            mealData: mealData,
            profile: profile,
            carbImpact: carbImpact,
            deviation: deviation,
            adjustedSensitivity: adjustedSensitivity,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )

        let uamForecast = [glucose] + uam.forecast(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            mealData: mealData,
            profile: profile,
            carbImpact: carbImpact,
            deviation: deviation,
            adjustedSensitivity: adjustedSensitivity,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )

        let ztForecast = [glucose] + zt.forecast(
            startingGlucose: glucose,
            glucoseImpactSeries: glucoseImpactSeries,
            mealData: mealData,
            profile: profile,
            carbImpact: carbImpact,
            deviation: deviation,
            adjustedSensitivity: adjustedSensitivity,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )

        let computedForecastSelection = Self.computeForecastSelection(
            iob: iobForecast,
            cob: cobForecast,
            uam: uamForecast,
            zt: ztForecast,
            currentGlucose: glucose
        )

        let carbImpactParams = CarbImpactParams.calculate(
            adjustedSensitivity: adjustedSensitivity,
            profile: profile,
            mealData: mealData,
            carbImpact: carbImpact,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )
        
        let carbImpactDuration = carbImpact > 0 ? min(
            carbImpactParams.remainingCarbAbsorptionTime * 60 / 5 / 2,
            max(0, mealData.mealCOB * carbImpactParams.carbSensivityFactor / carbImpact)
        ) : 0

        let blendedForecasts = Self.blendForecasts(
            selectionResult: computedForecastSelection,
            carbs: mealData.carbs,
            mealCOB: mealData.mealCOB,
            enableUAM: profile.enableUAM,
            carbImpactDuration: carbImpactDuration,
            remainingCarbImpactPeak: carbImpactParams.remainingCarbImpactPeak,
            fractionCarbsLeft: mealData.carbs > 0 ? mealData.mealCOB / mealData.carbs : 0,
            threshold: threshold,
            targetGlucose: profile.targetBg ?? 100,
            currentGlucose: glucose
        )

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
        maxMealAbsorptionTime: Decimal,
        mealCOB: Decimal,
        lastCarbTime: Date?,
        currentTime: Date
    ) -> Decimal {
        var minRemainingCarbAbsorptionTime: Decimal = min(3, maxMealAbsorptionTime) // hours
        if sensitivityRatio > 0 {
            minRemainingCarbAbsorptionTime = minRemainingCarbAbsorptionTime / sensitivityRatio
        }
        if mealCOB > 0 {
            let assumedCarbAbsorptionRate: Decimal = 20 // g/h
            minRemainingCarbAbsorptionTime = max(minRemainingCarbAbsorptionTime, mealCOB / assumedCarbAbsorptionRate)
        }
        var remainingCarbAbsorptionTime = minRemainingCarbAbsorptionTime
        if let lastCarbTime = lastCarbTime {
            let lastCarbAgeMin = Decimal(currentTime.timeIntervalSince(lastCarbTime) / 60)
            remainingCarbAbsorptionTime += 1.5 * (lastCarbAgeMin / 60)
        }
        return remainingCarbAbsorptionTime.rounded(toPlaces: 1)
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
        var s = series
        while s.count > lookback, s.suffix(2)[0] == s.suffix(2)[1] {
            s.removeLast()
        }
        return s
    }
}
