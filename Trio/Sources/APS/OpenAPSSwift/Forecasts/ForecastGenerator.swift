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
        profile: Profile
    ) -> ForecastResult {
        let carbImpact = mealData.currentDeviation * profile.carbRatio! / profile.sens!
        let deviation = mealData.currentDeviation

        return ForecastResult(
            iob: iob.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: deviation
            ),
            cob: cob.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: deviation
            ),
            uam: uam.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: deviation
            ),
            zt: zt.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: deviation
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
