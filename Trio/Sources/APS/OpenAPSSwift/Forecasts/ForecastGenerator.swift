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
        mealData: ComputedCarbs,
        profile: Profile,
        adjustedSensitivity: Decimal,
        sensitivityRatio: Decimal,
        currentTime: Date
    ) -> ForecastResult {
        let carbImpact = mealData.currentDeviation * (profile.carbRatio ?? profile.carbRatioFor(time: currentTime)) / (profile.sens ?? profile.sensitivityFor(time: currentTime))
        let deviation = mealData.currentDeviation

        return ForecastResult(
            iob: iob.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: deviation,
                adjustedSensitivity: adjustedSensitivity,
                sensitivityRatio: sensitivityRatio,
                currentTime: currentTime
            ),
            cob: cob.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: deviation,
                adjustedSensitivity: adjustedSensitivity,
                sensitivityRatio: sensitivityRatio,
                currentTime: currentTime
            ),
            uam: uam.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: deviation,
                adjustedSensitivity: adjustedSensitivity,
                sensitivityRatio: sensitivityRatio,
                currentTime: currentTime
            ),
            zt: zt.forecast(
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
