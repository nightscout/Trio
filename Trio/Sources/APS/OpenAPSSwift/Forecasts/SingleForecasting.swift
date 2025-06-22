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
    // TODO: Dynamic ISF not yet supported

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
    // TODO: Dynamic ISF not yet supported

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

        let carbImpactParams = CarbImpactParams.calculate(
            adjustedSensitivity: adjustedSensitivity,
            profile: profile,
            mealData: mealData,
            carbImpact: carbImpact,
            sensitivityRatio: sensitivityRatio,
            currentTime: currentTime
        )

        // How many intervals we spread the initial CI decay over?
        // We use twice the absorption window (so that by 2x the window, CI has decayed to zero).
        let decayIntervals = max(carbImpactParams.maxAbsorptionIntervals * 2, 1)

        // Helper: negative deviation only (never positive)
        let forecastedDeviation = min(0, deviation)

        // Build forecast out to glucoseImpactSeries.count (usually 48)
        for seriesCount in 1 ..< glucoseImpactSeries.count {
            let insulinEffect = glucoseImpactSeries[seriesCount]

            // Linearly decay the *observed* carb impact from initialCI → 0
            let decayFactor = max(0, 1 - seriesCount / decayIntervals)
            let forecastedCarbImpact = carbImpactParams.cappedCarbImpact * Decimal(decayFactor)

            // Add a simple triangle bump for remaining carbs:
            // – ramp up linearly to peak over the first half of the window,
            // – ramp down linearly over the second half,
            // – zero afterwards.
            let triangle: Decimal
            if carbImpactParams.triangleIntervals > 0, seriesCount <= carbImpactParams.triangleIntervals {
                // FIXME: integer division here might be slightly off for odd number intervals.
                // FIXME: For perfect symmetry we could use let halfTriangle = (triangleIntervals + 1) / 2 — Change this?!
                let halfTriangle = carbImpactParams.triangleIntervals / 2
                if seriesCount <= halfTriangle {
                    // Ramp up
                    triangle = carbImpactParams.remainingCarbImpactPeak * Decimal(seriesCount) / Decimal(halfTriangle)
                } else {
                    // Ramp down
                    triangle = carbImpactParams.remainingCarbImpactPeak * Decimal(carbImpactParams.triangleIntervals - seriesCount) / Decimal(halfTriangle)
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
}

/// Forecast sub-generator for “unannounced meal” impact (UAM)
struct UAMForecastGenerator: SingleForecasting {
    // TODO: Dynamic ISF not yet supported

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
    // TODO: Dynamic ISF not yet supported

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
