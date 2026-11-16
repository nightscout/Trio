import Foundation

/// Every chart type that can be exported to PDF, across all Statistics categories.
/// Used by the report builder and saved presets.
enum ReportChartType: String, Codable, CaseIterable, Identifiable {
    case glucoseDistributionByTime
    case glucosePercentileByTime
    case glucosePercentileByDay
    case glucoseDistributionByDay
    case glucoseGlycemiaRiskIndex
    case insulinTotalDailyDose
    case insulinBolusDistribution
    case loopingPerformance
    case mealsTotalMeals
    case therapyBasalRates
    case therapyGlucoseTargets
    case therapyCarbRatios
    case therapyInsulinSensitivities

    /// Therapy settings in export menu order.
    static let therapySettings: [Self] = [
        .therapyBasalRates,
        .therapyGlucoseTargets,
        .therapyCarbRatios,
        .therapyInsulinSensitivities
    ]

    var id: String { rawValue }

    init(_ type: Stat.StateModel.GlucoseChartType) {
        switch type {
        case .distributionByTime: self = .glucoseDistributionByTime
        case .percentileByTime: self = .glucosePercentileByTime
        case .percentileByDay: self = .glucosePercentileByDay
        case .distributionByDay: self = .glucoseDistributionByDay
        case .glycemiaRiskIndex: self = .glucoseGlycemiaRiskIndex
        }
    }

    init(_ type: Stat.StateModel.InsulinChartType) {
        switch type {
        case .totalDailyDose: self = .insulinTotalDailyDose
        case .bolusDistribution: self = .insulinBolusDistribution
        }
    }

    /// `nil` for Looping chart types that aren't exportable yet ("Coming soon").
    init?(_ type: Stat.StateModel.LoopingChartType) {
        switch type {
        case .loopingPerformance: self = .loopingPerformance
        case .cgmConnectionTrace,
             .trioUpTime: return nil
        }
    }

    /// `nil` for Meal chart types that aren't exportable yet ("Coming soon").
    init?(_ type: Stat.StateModel.MealChartType) {
        switch type {
        case .totalMeals: self = .mealsTotalMeals
        case .mealToHypoHyperDistribution: return nil
        }
    }

    /// Charts with one entry per day. Disabled for the single-day range, as on the
    /// Statistics screen (`StatRootView.intervalOptions`).
    var isPerDay: Bool {
        self == .glucosePercentileByDay || self == .glucoseDistributionByDay
    }

    /// False for therapy settings, which show the current schedule.
    var usesDateRange: Bool {
        category != .therapySettings
    }

    var category: ReportCategory {
        switch self {
        case .glucoseDistributionByDay,
             .glucoseDistributionByTime,
             .glucoseGlycemiaRiskIndex,
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
        case .therapyBasalRates,
             .therapyCarbRatios,
             .therapyGlucoseTargets,
             .therapyInsulinSensitivities:
            return .therapySettings
        }
    }

    /// Same localized names as the Statistics chart pickers and settings screens.
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
        case .glucoseGlycemiaRiskIndex:
            return Stat.StateModel.GlucoseChartType.glycemiaRiskIndex.displayName
        case .insulinTotalDailyDose:
            return Stat.StateModel.InsulinChartType.totalDailyDose.displayName
        case .insulinBolusDistribution:
            return Stat.StateModel.InsulinChartType.bolusDistribution.displayName
        case .loopingPerformance:
            return Stat.StateModel.LoopingChartType.loopingPerformance.displayName
        case .mealsTotalMeals:
            return Stat.StateModel.MealChartType.totalMeals.displayName
        case .therapyBasalRates:
            return String(localized: "Basal Rates")
        case .therapyGlucoseTargets:
            return String(localized: "Glucose Targets")
        case .therapyCarbRatios:
            return String(localized: "Carb Ratios")
        case .therapyInsulinSensitivities:
            return String(localized: "Insulin Sensitivities")
        }
    }
}

/// Export menu groups: the Statistics data types plus therapy settings.
enum ReportCategory: Hashable, Identifiable {
    case glucose
    case meals
    case insulin
    case looping
    case therapySettings

    /// Export menu order, which is also the PDF page order.
    static let exportOrder: [Self] = [.glucose, .meals, .insulin, .looping, .therapySettings]

    var id: Self { self }

    /// Name for the export menu and PDF header. Meals is shown as "Carbs", which is what
    /// its charts report.
    var displayName: String {
        switch self {
        case .glucose:
            return Stat.StateModel.StatisticViewType.glucose.displayName
        case .meals:
            return String(localized: "Carbs")
        case .insulin:
            return Stat.StateModel.StatisticViewType.insulin.displayName
        case .looping:
            return Stat.StateModel.StatisticViewType.looping.displayName
        case .therapySettings:
            return String(localized: "Therapy Settings")
        }
    }
}
