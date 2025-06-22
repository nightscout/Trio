import Foundation

/// Common interface for a single forecast pipeline
protocol SingleForecasting {
    /// - Parameters:
    ///   - startingGlucose: the current glucose
    ///   - glucoseImpactSeries:  the series of BGI (insulin effect) ticks
    ///   - mealData:   absorption & COB info
    ///   - profile:    user profile (for carbRatio, DIA, etc)
    ///   - carbImpact:         current carb impact (mg/dL per 5m)
    ///   - deviation:  current deviation (mg/dL per 5m)
    /// - Returns: a capped/clamped array of future BGs, one per 5-minute interval
    func forecast(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData: ComputedCarbs,
        profile: Profile,
        carbImpact: Decimal,
        deviation: Decimal,
        adjustedSensitivity: Decimal,
        sensitivityRatio: Decimal,
        currentTime: Date
    ) -> [Decimal]
}

/// Forecast sub-generator for insulin-only effect (IOB)
struct IOBForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData _: ComputedCarbs,
        profile _: Profile,
        carbImpact _: Decimal,
        deviation: Decimal,
        adjustedSensitivity _: Decimal,
        sensitivityRatio _: Decimal,
        currentTime _: Date
    ) -> [Decimal] {
        var result = [startingGlucose]
        for (count, glucoseImpact) in glucoseImpactSeries.enumerated() {
            let forecastedDeviation = deviation * (1 - min(1, Decimal(count) / (60 / 5)))
            let next = result.last! + glucoseImpact + forecastedDeviation
            result.append(next.clamp(lowerBound: 39, upperBound: 401))
        }
        return ForecastGenerator.trimFlatTails(result, lookback: 90 / 5)
    }
}

/// Forecast sub-generator for carb-only effect (COB + UAM piece)
struct COBForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData: ComputedCarbs,
        profile: Profile,
        carbImpact: Decimal,
        deviation: Decimal,
        adjustedSensitivity: Decimal,
        sensitivityRatio: Decimal,
        currentTime: Date
    ) -> [Decimal] {
        // Start with the current BG
        var result = [startingGlucose]

        let carbSensivityFactor = adjustedSensitivity / (profile.carbRatio ?? profile.carbRatioFor(time: currentTime))

        // Initial carb impact in mg/dL per 5m
        let initialCarbImpact = carbImpact * carbSensivityFactor
        let maxCarbAbsorptionRate: Decimal = 30 // g/h
        let maxCarbImpact = (maxCarbAbsorptionRate * carbSensivityFactor * 5 / 60).rounded(toPlaces: 1)
        let cappedCarbImpact = min(initialCarbImpact, maxCarbImpact)

        let computedRemainingCarbAbsorptionTime = Self.calculateRemainingCarbAbsorptionTime(
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

        // How many intervals we spread the initial CI decay over?
        // We use twice the absorption window (so that by 2x the window, CI has decayed to zero).
        let decayIntervals = max(maxAbsorptionIntervals * 2, 1)

        // Helper: negative deviation only (never positive)
        let forecastedDeviation = min(0, deviation)

        // Build forecast out to glucoseImpactSeries.count (usually 48)
        for seriesCount in 1 ..< glucoseImpactSeries.count {
            let insulinEffect = glucoseImpactSeries[seriesCount]

            // Linearly decay the *observed* carb impact from initialCI → 0
            let decayFactor = max(0, 1 - seriesCount / decayIntervals)
            let forecastedCarbImpact = cappedCarbImpact * Decimal(decayFactor)

            // Add a simple triangle bump for remaining carbs:
            // – ramp up linearly to peak over the first half of the window,
            // – ramp down linearly over the second half,
            // – zero afterwards.
            let triangle: Decimal
            if triangleIntervals > 0, seriesCount <= triangleIntervals {
                // FIXME: integer division here might be slightly off for odd number intervals.
                // FIXME: For perfect symmetry we could use let halfTriangle = (triangleIntervals + 1) / 2 — Change this?!
                let halfTriangle = triangleIntervals / 2
                if seriesCount <= halfTriangle {
                    // Ramp up
                    triangle = remainingCarbImpactPeak * Decimal(seriesCount) / Decimal(halfTriangle)
                } else {
                    // Ramp down
                    triangle = remainingCarbImpactPeak * Decimal(triangleIntervals - seriesCount) / Decimal(halfTriangle)
                }
            } else {
                triangle = 0
            }

            let next = result.last!
                + insulinEffect
                + forecastedDeviation
                + forecastedCarbImpact
                + triangle

            result.append(next.clamp(lowerBound: 39, upperBound: 1500))
        }

        return ForecastGenerator.trimFlatTails(result, lookback: 12)
    }

    /// Calculates the dynamic remaining carb absorption time in hours, per oref0 logic.
    /// - Parameters:
    ///   - sensitivityRatio: ratio from autosens (usually 1.0 if not present)
    ///   - mealCOB: unabsorbed carbs (grams)
    ///   - lastCarbTime: timestamp of last carb entry (Date? or nil)
    ///   - currentTime: now
    /// - Returns: Remaining CA time in hours (Decimal)
    private static func calculateRemainingCarbAbsorptionTime(
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
}

/// Forecast sub-generator for “unannounced meal” impact (UAM)
struct UAMForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData: ComputedCarbs,
        profile _: Profile,
        carbImpact: Decimal,
        deviation: Decimal,
        adjustedSensitivity _: Decimal,
        sensitivityRatio _: Decimal,
        currentTime _: Date
    ) -> [Decimal] {
        var result = [startingGlucose]

        let slope = min(deviation, -(mealData.slopeFromMinDeviation / 3))
        for seriesCount in 1 ..< 48 {
            let forecastedGlucoseImpact = glucoseImpactSeries[seriesCount]
            let forecastedUnannouncedCarbImpact = max(0, carbImpact + slope * Decimal(seriesCount))
            let next = result.last! + forecastedGlucoseImpact + min(0, deviation) + forecastedUnannouncedCarbImpact
            result.append(next.clamp(lowerBound: 39, upperBound: 401))
        }

        return ForecastGenerator.trimFlatTails(result, lookback: 12)
    }
}

/// Forecast sub-generator for “zero-temp” baseline (ZT)
struct ZTForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData: ComputedCarbs,
        profile: Profile,
        carbImpact: Decimal,
        deviation: Decimal,
        adjustedSensitivity: Decimal,
        sensitivityRatio: Decimal,
        currentTime: Date
    ) -> [Decimal] {
        // essentially insulin effect only, but with zero-temp ISF if needed
        IOBForecastGenerator().forecast(
            startingGlucose: startingGlucose,
            glucoseImpactSeries: glucoseImpactSeries.map { /* TODO: use iobWithZeroTemp.activity */ $0 },
            mealData: mealData,
            profile: profile,
            carbImpact: carbImpact,
            deviation: deviation,
            adjustedSensitivity: adjustedSensitivity,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )
    }
}
