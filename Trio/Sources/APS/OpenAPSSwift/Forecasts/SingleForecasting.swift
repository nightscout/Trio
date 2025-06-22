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
        deviation: Decimal
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
        deviation: Decimal
    ) -> [Decimal] {
        var result = [startingGlucose]
        for (count, glucoseImpact) in glucoseImpactSeries.enumerated() {
            let predDev = deviation * (1 - min(1, Decimal(count) / (60 / 5)))
            let next = result.last! + glucoseImpact + predDev
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
        deviation: Decimal
    ) -> [Decimal] {
        // Start with the current BG
        var result = [startingGlucose]

        // carb-sensitivity factor (mg/dL per gram)
        guard let sens = profile.sens,
              let carbRatio = profile.carbRatio
        else {
            fatalError("Profile must have sens and carbRatio")
        }
        let csf = sens / carbRatio // FIXME: this needs to be the AS-adjusted sens, not profile.sens

        // Initial carb impact in mg/dL per 5m
        let initialCarbImpact = carbImpact * csf

        // Number of 5-minute intervals over which we expect *all* carbs to absorb
        let absorptionIntervals = Int(profile.maxMealAbsorptionTime * Decimal(60) / 5)

        // Peak impact (mg/dL per 5m) of the *remaining* carbs
        let remainingCarbImpactPeak = mealData.mealCOB * csf

        // How many intervals we spread the initial CI decay over?
        // We use twice the absorption window (so that by 2× the window, CI has decayed to zero).
        let decayIntervals = max(absorptionIntervals * 2, 1)

        // Helper: negative deviation only (never positive)
        let predDev = min(0, deviation)

        // Build prediction out to glucoseImpactSeries.count (usually 48)
        for seriesCount in 1 ..< glucoseImpactSeries.count {
            let insulinEffect = glucoseImpactSeries[seriesCount]

            // Linearly decay the *observed* carb impact from initialCI → 0
            let decayFactor = max(0, 1 - seriesCount / decayIntervals)
            let forecastedCarbImpact = initialCarbImpact * Decimal(decayFactor)

            // Add a simple triangle bump for remaining carbs:
            // – ramp up linearly to peak over the first half of the window,
            // – ramp down linearly over the second half,
            // – zero afterwards.
            let triangle: Decimal
            if seriesCount <= absorptionIntervals {
                triangle = remainingCarbImpactPeak * (Decimal(seriesCount) / Decimal(absorptionIntervals))
            } else if seriesCount <= decayIntervals {
                triangle = remainingCarbImpactPeak * (Decimal(decayIntervals - seriesCount) / Decimal(absorptionIntervals))
            } else {
                triangle = 0
            }

            let next = result.last!
                + insulinEffect
                + predDev
                + forecastedCarbImpact
                + triangle

            result.append(next.clamp(lowerBound: 39, upperBound: 1500))
        }

        return ForecastGenerator.trimFlatTails(result, lookback: 12)
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
        deviation: Decimal
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
        deviation: Decimal
    ) -> [Decimal] {
        // essentially insulin effect only, but with zero-temp ISF if needed
        IOBForecastGenerator().forecast(
            startingGlucose: startingGlucose,
            glucoseImpactSeries: glucoseImpactSeries.map { /* TODO: use iobWithZeroTemp.activity */ $0 },
            mealData: mealData,
            profile: profile,
            carbImpact: carbImpact,
            deviation: deviation
        )
    }
}
