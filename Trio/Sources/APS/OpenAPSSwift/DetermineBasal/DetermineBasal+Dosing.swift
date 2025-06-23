import Foundation

extension DeterminationGenerator {
    struct DosingMetrics {
        var rate: Decimal?
        var duration: Decimal?
        var units: Decimal? // microbolus
        var insulinReq: Decimal?
        var carbsReq: Decimal?
        var reason: String
        var manualBolusErrorString: Int?
        var insulinForManualBolus: Decimal?
        var minGuardBG: Decimal?
        var minPredBG: Decimal?
        var smbEnabled: Bool
    }

    static func determineDosing(
        profile: Profile,
        currentTemp: TempBasal,
        iobData: IobResult,
        mealData: ComputedCarbs,
        autosensData: Autosens,
        forecastResult: ForecastResult,
        glucoseStatus: GlucoseStatus,
        enableSMB: Bool,
        currentTime: Date
    ) -> DosingMetrics? {
        return nil
    }

}
