import Foundation

extension ForecastGenerator {
    // TODO: Dynamic ISF not yet supported

    static func forecastIOB(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        carbImpact: Decimal,
    ) -> [Decimal] {
        var result = [startingGlucose]
        for glucoseImpact in glucoseImpactSeries {
            let forecastedDeviation = carbImpact * (1 - min(1, Decimal(result.count) / (60 / 5)))
            let next = result.last! + glucoseImpact.jsRounded(scale: 2) + forecastedDeviation
            if result.count < 48 { result.append(next) }
        }
        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 401) }
        return ForecastGenerator.trimFlatTails(clampedResult, lookback: 13)
    }

    static func forecastCOB(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        carbImpact: Decimal,
        carbImpactParams: CarbImpactParams
    ) -> [Decimal] {
        // Start with the current BG
        var result = [startingGlucose]

        // Build forecast out to glucoseImpactSeries.count (usually 48)
        for glucoseImpact in glucoseImpactSeries {
            let forecastedDeviation = carbImpact * (1 - min(1, Decimal(result.count) / (60 / 5)))

            // Linearly decay the *observed* carb impact from initialCI → 0
            // var predCI = Math.max(0, Math.max(0,ci) * ( 1 - COBpredBGs.length/Math.max(cid*2,1) ) );
            let decayFactor = max(0, 1 - Decimal(result.count) / max(carbImpactParams.carbImpactDuration * 2, Decimal(1)))
            let forecastedCarbImpact = max(0, max(0, carbImpact) * decayFactor)

            // Add a simple triangle bump for remaining carbs:
            // – ramp up linearly to peak over the first half of the window,
            // – ramp down linearly over the second half,
            // – zero afterwards.
            let triangle: Decimal
            if carbImpactParams.triangleIntervals > 0, result.count <= carbImpactParams.triangleIntervals {
                // FIXME: integer division here might be slightly off for odd number intervals.
                // FIXME: For perfect symmetry we could use let halfTriangle = (triangleIntervals + 1) / 2 — Change this?!
                let halfTriangle = carbImpactParams.triangleIntervals / 2
                if result.count <= halfTriangle {
                    // Ramp up
                    triangle = carbImpactParams.remainingCarbImpactPeak * Decimal(result.count) / Decimal(halfTriangle)
                } else {
                    // Ramp down
                    triangle = carbImpactParams
                        .remainingCarbImpactPeak * Decimal(carbImpactParams.triangleIntervals - result.count) /
                        Decimal(halfTriangle)
                }
            } else {
                triangle = 0
            }

            let next = result.last!
                + glucoseImpact.jsRounded(scale: 2)
                + min(0, forecastedDeviation)
                + forecastedCarbImpact
                + triangle

            if result.count < 48 { result.append(next) }
        }

        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 1500) }
        return ForecastGenerator.trimFlatTails(clampedResult, lookback: 12)
    }

    static func forecastUAM(
        startingGlucose: Decimal,
        glucoseImpactSeries: [Decimal],
        mealData: ComputedCarbs,
        uamCarbImpact: Decimal,
        carbImpact: Decimal
    ) -> [Decimal] {
        var result = [startingGlucose]

        let slopeFromDeviations = min(mealData.slopeFromMaxDeviation, -mealData.slopeFromMinDeviation / 3)
        let ticksInThreeHours: Decimal = 36 // 3 * 60 / 5

        let unannouncedCarbImpact = uamCarbImpact

        for glucoseImpact in glucoseImpactSeries {
            let forecastedDeviation = carbImpact * (1 - min(1, Decimal(result.count) / (60 / 5)))

            // In JS: predUCIslope = max(0, uci + (tick * slopeFromDeviations))
            let forecastedUnannouncedCarbImpactSlope = max(
                0,
                unannouncedCarbImpact + Decimal(result.count) * slopeFromDeviations
            )

            // In JS: predUCImax = max(0, uci * (1 - tick / ticksInThreeHours))
            let maxForecastedUnannouncedCarbImpact = max(
                0,
                unannouncedCarbImpact * (1 - Decimal(result.count) / ticksInThreeHours)
            )
            let forecastedUnannouncedCarbImpact = min(
                forecastedUnannouncedCarbImpactSlope,
                maxForecastedUnannouncedCarbImpact
            )

            let next = result.last! + glucoseImpact
                .jsRounded(scale: 2) + min(0, forecastedDeviation) + forecastedUnannouncedCarbImpact

            if result.count < 48 { result.append(next) }
        }

        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 401) }
        return ForecastGenerator.trimFlatTails(clampedResult, lookback: 12)
    }

    static func forecastZT(
        startingGlucose: Decimal,
        glucoseImpactSeriesWithZeroTemp: [Decimal],
        targetBG: Decimal
    ) -> [Decimal] {
        var result = [startingGlucose]
        for glucoseImpact in glucoseImpactSeriesWithZeroTemp {
            // Potential bug: ZT doesn't use forecastedDeviation like IoB does
            let next = result.last! + glucoseImpact.jsRounded(scale: 2)
            if result.count < 48 { result.append(next) }
        }
        let clampedResult = result.map { $0.clamp(lowerBound: 39, upperBound: 401) }
        return ForecastGenerator.trimZTTails(series: clampedResult, targetBG: targetBG)
    }
}
