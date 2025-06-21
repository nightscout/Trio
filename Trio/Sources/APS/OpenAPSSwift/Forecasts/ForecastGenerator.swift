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
        glucose: Double,
        glucoseImpactSeries: [Double],
        mealData: ComputedCarbs,
        profile: Profile
    ) -> ForecastResult {
        let carbImpact = Double(mealData.currentDeviation) * Double(profile.carbRatio!) / Double(profile.sens!)
        let deviation = mealData.currentDeviation

        return ForecastResult(
            iob: iob.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: Double(deviation)
            ),
            cob: cob.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: Double(deviation)
            ),
            uam: uam.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: Double(deviation)
            ),
            zt: zt.forecast(
                startingGlucose: glucose,
                glucoseImpactSeries: glucoseImpactSeries,
                mealData: mealData,
                profile: profile,
                carbImpact: carbImpact,
                deviation: Double(deviation)
            )
        )
    }

    /// Trims trailing flat-line points beyond a “lookback” count
    public static func trimFlatTails(_ series: [Double], lookback: Int) -> [Double] {
        var s = series
        while s.count > lookback, s.suffix(2)[0] == s.suffix(2)[1] {
            s.removeLast()
        }
        return s
    }
}
