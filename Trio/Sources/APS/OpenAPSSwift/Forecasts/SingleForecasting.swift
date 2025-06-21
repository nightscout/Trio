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
        startingGlucose: Double,
        glucoseImpactSeries: [Double],
        mealData: ComputedCarbs,
        profile: Profile,
        carbImpact: Double,
        deviation: Double
    ) -> [Double]
}

/// Forecast sub-generator for insulin-only effect (IOB)
struct IOBForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Double,
        glucoseImpactSeries: [Double],
        mealData _: ComputedCarbs,
        profile _: Profile,
        carbImpact _: Double,
        deviation: Double
    ) -> [Double] {
        var result = [startingGlucose]
        for (count, glucoseImpact) in glucoseImpactSeries.enumerated() {
            let predDev = deviation * (1 - min(1, Double(count) / (60 / 5)))
            let next = result.last! + glucoseImpact + predDev
            result.append(next.clamp(lowerBound: 39, upperBound: 401))
        }
        return ForecastGenerator.trimFlatTails(result, lookback: 90 / 5)
    }
}

/// Forecast sub-generator for carb-only effect (COB + UAM piece)
struct COBForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Double,
        glucoseImpactSeries: [Double],
        mealData _: ComputedCarbs,
        profile: Profile,
        carbImpact: Double,
        deviation: Double
    ) -> [Double] {
        var result = [startingGlucose]

        guard let sensitivity = profile.sens else {
            fatalError("Profile must have a `sens` value")
        }

        guard let carbRatio = profile.carbRatio else {
            fatalError("Profile must have a `carbRatio` value")
        }

        let carbSensivityFactor = Double(sensitivity) / Double(carbRatio)

        // FIXME: compute these
        let carbImpactDuration = 100
        let remainingCarbImpactPeak = 100

        for i in 1 ..< 48 {
            let forecastedGlucoseImpact = glucoseImpactSeries[i]
            // linear drop-off of carb impact over carbImpactDuration*2 intervals

            let numerator = Double(carbImpact * (1 - Double(i)))
            let denominator = Double(max(carbImpactDuration * 2, 1))
            let rawDecay = numerator / denominator
            let carbDecay = Double(max(0, rawDecay))

            // add the "triangle" bump up to remainingCarbImpactPeak
            let remainingCarbImpact = i < Int(carbImpactDuration * 2)
                ? remainingCarbImpactPeak * (Int(Double(i)) / (carbImpactDuration * 2))
                : 0

            let next = result
                .last! + Double(carbImpactDuration) + Double(min(0, deviation)) + carbDecay + Double(remainingCarbImpact)
            result.append(next.clamp(lowerBound: 39, upperBound: 1500))
        }

        return ForecastGenerator.trimFlatTails(result, lookback: 12) // stop at plateau
    }
}

/// Forecast sub-generator for “unannounced meal” impact (UAM)
struct UAMForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Double,
        glucoseImpactSeries: [Double],
        mealData: ComputedCarbs,
        profile _: Profile,
        carbImpact: Double,
        deviation: Double
    ) -> [Double] {
        var result = [startingGlucose]

        let slope = min(deviation, -(Double(mealData.slopeFromMinDeviation) / 3))
        for i in 1 ..< 48 {
            let forecastedGlucoseImpact = glucoseImpactSeries[i]
            let forecastedUnannouncedCarbImpact = max(0, carbImpact + slope * Double(i))
            let next = result.last! + forecastedGlucoseImpact + min(0, deviation) + forecastedUnannouncedCarbImpact
            result.append(next.clamp(lowerBound: 39, upperBound: 401))
        }

        return ForecastGenerator.trimFlatTails(result, lookback: 12)
    }
}

/// Forecast sub-generator for “zero-temp” baseline (ZT)
struct ZTForecastGenerator: SingleForecasting {
    public func forecast(
        startingGlucose: Double,
        glucoseImpactSeries: [Double],
        mealData: ComputedCarbs,
        profile: Profile,
        carbImpact: Double,
        deviation: Double
    ) -> [Double] {
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
