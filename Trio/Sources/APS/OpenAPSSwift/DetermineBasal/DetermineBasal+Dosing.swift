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
        profile _: Profile,
        currentTemp _: TempBasal,
        iobData _: IobResult,
        mealData _: ComputedCarbs,
        autosensData _: Autosens,
        forecastResult _: ForecastResult,
        glucoseStatus _: GlucoseStatus,
        enableSMB _: Bool,
        currentTime _: Date
    ) -> DosingMetrics? {
        nil
    }
}
