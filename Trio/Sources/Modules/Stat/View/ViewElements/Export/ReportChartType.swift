import Foundation

/// A single flat identifier for every chart type currently exportable to PDF, spanning all four
/// Statistics categories. Backs both the report builder's working item list and saved presets —
/// one source of truth here avoids juggling four separate per-category chart-type enums
/// (`Stat.StateModel.GlucoseChartType`, `InsulinChartType`, `LoopingChartType`, `MealChartType`)
/// wherever a report item needs to be stored, compared, or persisted.
enum ReportChartType: String, Codable, CaseIterable, Identifiable {
    case glucoseDistributionByTime
    case glucosePercentileByTime
    case glucosePercentileByDay
    case glucoseDistributionByDay
    case insulinTotalDailyDose
    case insulinBolusDistribution
    case loopingPerformance
    case mealsTotalMeals

    var id: String { rawValue }

    var dataType: Stat.StateModel.StatisticViewType {
        switch self {
        case .glucoseDistributionByDay,
             .glucoseDistributionByTime,
             .glucosePercentileByDay,
             .glucosePercentileByTime:
            return .glucose
        case .insulinBolusDistribution,
             .insulinTotalDailyDose:
            return .insulin
        case .loopingPerformance:
            return .looping
        case .mealsTotalMeals:
            return .meals
        }
    }

    /// Reuses the same localized display names already shown by the on-screen Statistics
    /// Chart Type pickers, so a report item's label always matches app-wide terminology.
    var displayName: String {
        switch self {
        case .glucoseDistributionByTime:
            return Stat.StateModel.GlucoseChartType.distributionByTime.displayName
        case .glucosePercentileByTime:
            return Stat.StateModel.GlucoseChartType.percentileByTime.displayName
        case .glucosePercentileByDay:
            return Stat.StateModel.GlucoseChartType.percentileByDay.displayName
        case .glucoseDistributionByDay:
            return Stat.StateModel.GlucoseChartType.distributionByDay.displayName
        case .insulinTotalDailyDose:
            return Stat.StateModel.InsulinChartType.totalDailyDose.displayName
        case .insulinBolusDistribution:
            return Stat.StateModel.InsulinChartType.bolusDistribution.displayName
        case .loopingPerformance:
            return Stat.StateModel.LoopingChartType.loopingPerformance.displayName
        case .mealsTotalMeals:
            return Stat.StateModel.MealChartType.totalMeals.displayName
        }
    }
}
