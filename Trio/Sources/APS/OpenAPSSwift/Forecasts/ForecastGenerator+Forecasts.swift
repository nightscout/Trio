import Foundation

extension ForecastGenerator {
    // TODO: Dynamic ISF not yet supported

    static func forecastIOB(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        deviation: Decimal,
    ) -> [Decimal] {
        var result = [startingGlucose]
        for (count, glucoseImpact) in glucoseImpactSeries.enumerated() {
            let forecastedDeviation = deviation * (1 - min(1, Decimal(count) / (60 / 5)))
            let next = result.last! + glucoseImpact + forecastedDeviation
            result.append(next.clamp(lowerBound: 39, upperBound: 401))
        }
        return ForecastGenerator.trimFlatTails(result, lookback: 90 / 5)
    }

    static func forecastCOB(
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
                    triangle = carbImpactParams
                        .remainingCarbImpactPeak * Decimal(carbImpactParams.triangleIntervals - seriesCount) /
                        Decimal(halfTriangle)
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

    static func forecastUAM(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData: ComputedCarbs,
        carbImpact: Decimal,
        deviation: Decimal
    ) -> [Decimal] {
        var result = [startingGlucose]

        let slopeFromDeviations = mealData.slopeFromMinDeviation
        let ticksInThreeHours: Decimal = 36 // 3 * 60 / 5

        let unannouncedCarbImpact = carbImpact

        for glucoseImpact in 1 ..< glucoseImpactSeries.count {
            let insulinEffect = glucoseImpactSeries[glucoseImpact]
            let forecastedDeviaton = min(0, deviation)

            // In JS: predUCIslope = max(0, uci + (tick * slopeFromDeviations))
            let forecastedUnannouncedCarbImpactSlope = max(
                0,
                unannouncedCarbImpact + Decimal(glucoseImpact) * slopeFromDeviations
            )

            // In JS: predUCImax = max(0, uci * (1 - tick / ticksInThreeHours))
            let maxForecastedUnannouncedCarbImpact = max(
                0,
                unannouncedCarbImpact * (1 - Decimal(glucoseImpact) / ticksInThreeHours)
            )
            let forecastedUnannouncedCarbImpact = min(
                forecastedUnannouncedCarbImpactSlope,
                maxForecastedUnannouncedCarbImpact
            )

            let next = result.last! + insulinEffect + forecastedDeviaton + forecastedUnannouncedCarbImpact

            result.append(next.clamp(lowerBound: 39, upperBound: 401))
        }

        return ForecastGenerator.trimFlatTails(result, lookback: 12)
    }

    static func forecastZT(
        startingGlucose: Decimal,
        glucoseImpactSeriesWithZeroTemp: [Decimal],
        deviation: Decimal
    ) -> [Decimal] {
        // essentially insulin effect only, but with zero-temp ISF if needed
        Self.forecastIOB(
            startingGlucose: startingGlucose,
            glucoseImpactSeries: glucoseImpactSeriesWithZeroTemp,
            deviation: deviation
        )
    }
}
