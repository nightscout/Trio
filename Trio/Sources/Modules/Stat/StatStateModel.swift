import Foundation
import Observation

extension Stat {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var highLimit: Decimal = 180
        var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
        var units: GlucoseUnits = .mgdL
        var timeInRangeType: TimeInRangeType = .timeInTightRange
        var useFPUconversion: Bool = false
        var glucoseFromPersistence: [GlucoseReading] = []
        var hourlyStats: [HourlyStats] = []
        var glucoseRangeStats: [GlucoseRangeStats] = []

        var hourlyLoopStats: [LoopingStats] = []
        var dailyLoopStats: [LoopingStats] = []

        var hourlyMealStats: [MealStats] = []
        var dailyMealStats: [MealStats] = []

        var hourlyTDDStats: [TDDStats] = []
        var dailyTDDStats: [TDDStats] = []

        var hourlyBolusStats: [BolusStats] = []
        var dailyBolusStats: [BolusStats] = []

        var dailyGlucosePercentileStats: [GlucoseDailyPercentileStats] = []
        var dailyGlucoseDistributionStats: [GlucoseDailyDistributionStats] = []
        var glucoseReadingsByDay: [Date: [GlucoseReading]] = [:]

        var selectedIntervalForGlucoseStats: StatsTimeIntervalWithToday = .today {
            didSet {
                setupGlucoseArray(for: selectedIntervalForGlucoseStats)
            }
        }

        var selectedIntervalForInsulinStats: StatsTimeInterval = .day

        var selectedIntervalForMealStats: StatsTimeInterval = .day

        var selectedIntervalForLoopStats: StatsTimeInterval = .day

        var selectedGlucoseChartType: GlucoseChartType = .percentileByTime

        var selectedInsulinChartType: InsulinChartType = .totalDailyDose

        var selectedLoopingChartType: LoopingChartType = .loopingPerformance

        var selectedMealChartType: MealChartType = .totalMeals

        override func subscribe() {
            highLimit = settingsManager.settings.high
            units = settingsManager.settings.units
            eA1cDisplayUnit = settingsManager.settings.eA1cDisplayUnit
            useFPUconversion = settingsManager.settings.useFPUconversion
            timeInRangeType = settingsManager.settings.timeInRangeType

            // open on the span the home stats panel reports
            let range = settingsManager.settings.homeStatsPanelRange
            selectedIntervalForInsulinStats = StatsTimeInterval(range)
            selectedIntervalForMealStats = StatsTimeInterval(range)
            selectedIntervalForLoopStats = StatsTimeInterval(range)

            // `didSet` starts these fetches; assign only on change so each runs exactly once
            let glucoseInterval = StatsTimeIntervalWithToday(range)
            if glucoseInterval != selectedIntervalForGlucoseStats {
                selectedIntervalForGlucoseStats = glucoseInterval
            } else {
                setupGlucoseArray(for: glucoseInterval)
            }

            setupTDDStats()
            setupBolusStats()
            setupLoopStats()
            setupMealStats()
            setupGlucoseDailyStats()
        }
    }
}

// MARK: Stats Types + Enums

extension Stat.StateModel {
    enum GlucoseChartType: String, CaseIterable {
        case percentileByTime = "Percentile"
        case distributionByTime = "Distribution"
        /// Glycemia Risk Index for the selected period
        case glycemiaRiskIndex = "Glycemia Risk Index"
        /// Day-based box plot of glucose percentile ranges
        case percentileByDay = "Percentile (by day)"
        case distributionByDay = "Distribution (by day)"

        var isDaily: Bool { self == .percentileByDay || self == .distributionByDay }

        var displayName: String {
            switch self {
            case .percentileByTime:
                return String(localized: "Percentile")
            case .distributionByTime:
                return String(localized: "Distribution")
            case .glycemiaRiskIndex:
                return String(localized: "Glycemia Risk Index")
            case .percentileByDay:
                return String(localized: "Percentile (by day)")
            case .distributionByDay:
                return String(localized: "Distribution (by day)")
            }
        }
    }

    enum InsulinChartType: String, CaseIterable {
        case totalDailyDose = "Total Daily Dose"
        case bolusDistribution = "Bolus Distribution"

        var displayName: String {
            switch self {
            case .totalDailyDose:
                return String(localized: "Total Daily Dose")
            case .bolusDistribution:
                return String(localized: "Bolus Distribution")
            }
        }
    }

    enum LoopingChartType: String, CaseIterable {
        case loopingPerformance = "Looping Performance"
        case cgmConnectionTrace = "CGM Connection Trace"
        case trioUpTime = "Trio Up-Time"

        var displayName: String {
            switch self {
            case .loopingPerformance:
                return String(localized: "Looping Performance")
            case .cgmConnectionTrace:
                return String(localized: "CGM Connection Trace")
            case .trioUpTime:
                return String(localized: "Trio Up-Time")
            }
        }
    }

    enum MealChartType: String, CaseIterable {
        case totalMeals = "Total Meals"
        case mealToHypoHyperDistribution = "Meal to Hypo/Hyper"

        var displayName: String {
            switch self {
            case .totalMeals:
                return String(localized: "Total Meals")
            case .mealToHypoHyperDistribution:
                return String(localized: "Meal to Hypo/Hyper")
            }
        }
    }

    enum StatsTimeIntervalWithToday: String, CaseIterable, Identifiable {
        case today
        case day = "D"
        case week = "W"
        case month = "M"
        case total = "3 M"

        var id: Self { self }

        init(_ range: HomeStatsPanelRange) {
            switch range {
            case .today: self = .today
            case .day: self = .day
            case .week: self = .week
            case .month: self = .month
            case .threeMonths: self = .total
            }
        }

        var displayName: String {
            switch self {
            case .today:
                return String(localized: "Today")
            case .day:
                return String(localized: "D", comment: "Abbreviation for day")
            case .week:
                return String(localized: "W", comment: "Abbreviation for week")
            case .month:
                return String(localized: "M", comment: "Abbreviation for month")
            case .total:
                return String(localized: "3 M", comment: "Abbreviation for three months")
            }
        }
    }

    enum StatsTimeInterval: String, CaseIterable, Identifiable {
        case day = "D"
        case week = "W"
        case month = "M"
        case total = "3 M"

        var id: Self { self }

        /// No "today" bucket here, so it falls back to the day view.
        init(_ range: HomeStatsPanelRange) {
            switch range {
            case .day,
                 .today: self = .day
            case .week: self = .week
            case .month: self = .month
            case .threeMonths: self = .total
            }
        }

        var displayName: String {
            switch self {
            case .day:
                return String(localized: "D", comment: "Abbreviation for day")
            case .week:
                return String(localized: "W", comment: "Abbreviation for week")
            case .month:
                return String(localized: "M", comment: "Abbreviation for month")
            case .total:
                return String(localized: "3 M", comment: "Abbreviation for three months")
            }
        }
    }

    enum StatisticViewType: String, CaseIterable, Identifiable {
        case glucose
        case insulin
        case looping
        case meals

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .glucose:
                return String(localized: "Glucose", comment: "Title for glucose-related statistics")
            case .insulin:
                return String(localized: "Insulin", comment: "Title for insulin-related statistics")
            case .looping:
                return String(localized: "Looping", comment: "Title for looping and system statistics")
            case .meals:
                return String(localized: "Meals", comment: "Title for meal-related statistics")
            }
        }
    }
}
