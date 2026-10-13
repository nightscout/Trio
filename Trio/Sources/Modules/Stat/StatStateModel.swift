import Foundation
import Observation
import SwiftUI

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

        // Cache for Loop Stats
        var hourlyLoopStats: [LoopingStats] = []
        var dailyLoopStats: [LoopingStats] = []

        // Cache for Meal Stats
        var hourlyMealStats: [MealStats] = []
        var dailyMealStats: [MealStats] = []

        // Cache for TDD Stats
        var hourlyTDDStats: [TDDStats] = []
        var dailyTDDStats: [TDDStats] = []

        // Cache for Bolus Stats
        var hourlyBolusStats: [BolusStats] = []
        var dailyBolusStats: [BolusStats] = []

        // Cache for Glucose Daily Stats
        var dailyGlucosePercentileStats: [GlucoseDailyPercentileStats] = []
        var dailyGlucoseDistributionStats: [GlucoseDailyDistributionStats] = []
        var glucoseReadingsByDay: [Date: [GlucoseReading]] = [:]

        // Selected Duration for Glucose Stats
        var selectedIntervalForGlucoseStats: StatsTimeIntervalWithToday = .today {
            didSet {
                setupGlucoseArray(for: selectedIntervalForGlucoseStats)
            }
        }

        // Selected Duration for Insulin Stats
        var selectedIntervalForInsulinStats: StatsTimeInterval = .day

        // Selected Duration for Meal Stats
        var selectedIntervalForMealStats: StatsTimeInterval = .day

        // Selected Duration for Loop Stats
        var selectedIntervalForLoopStats: StatsTimeInterval = .day

        // Selected Glucose Chart Type
        var selectedGlucoseChartType: GlucoseChartType = .percentileByTime

        // Selected Insulin Chart Type
        var selectedInsulinChartType: InsulinChartType = .totalDailyDose

        // Selected Looping Chart Type
        var selectedLoopingChartType: LoopingChartType = .loopingPerformance

        // Selected Meal Chart Type
        var selectedMealChartType: MealChartType = .totalMeals

        override func subscribe() {
            highLimit = settingsManager.settings.high
            units = settingsManager.settings.units
            eA1cDisplayUnit = settingsManager.settings.eA1cDisplayUnit
            useFPUconversion = settingsManager.settings.useFPUconversion
            timeInRangeType = settingsManager.settings.timeInRangeType

            setupGlucoseArray(for: .today)
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
    /// Defines the available types of glucose charts
    enum GlucoseChartType: String, CaseIterable {
        /// Ambulatory Glucose Profile showing percentile ranges
        case percentileByTime = "Percentile"
        /// Time-based distribution of glucose ranges
        case distributionByTime = "Distribution"
        /// Day-based box plot of glucose percentile ranges
        case percentileByDay = "Percentile (by day)"
        /// Day-based distribution of glucose ranges
        case distributionByDay = "Distribution (by day)"

        var displayName: String {
            switch self {
            case .percentileByTime:
                return String(localized: "Percentile")
            case .distributionByTime:
                return String(localized: "Distribution")
            case .percentileByDay:
                return String(localized: "Percentile (by day)")
            case .distributionByDay:
                return String(localized: "Distribution (by day)")
            }
        }
    }

    /// Defines the available types of insulin charts
    enum InsulinChartType: String, CaseIterable {
        /// Shows total daily insulin doses
        case totalDailyDose = "Total Daily Dose"
        /// Shows distribution of bolus types
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

    /// Defines the available types of looping charts
    enum LoopingChartType: String, CaseIterable {
        /// Shows loop completion and success rates
        case loopingPerformance = "Looping Performance"
        /// Shows CGM connection status over time
        case cgmConnectionTrace = "CGM Connection Trace"
        /// Shows Trio pump uptime statistics
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

    /// Defines the available types of meal charts
    enum MealChartType: String, CaseIterable {
        /// Shows total meal statistics
        case totalMeals = "Total Meals"
        /// Shows correlation between meals and glucose excursions
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

    /// Defines the available time periods for duration-based statistics including 'Today' (time since midnight until now)
    enum StatsTimeIntervalWithToday: String, CaseIterable, Identifiable {
        /// Current day
        case today
        /// Single day view
        case day = "D"
        /// Week view
        case week = "W"
        /// Month view
        case month = "M"
        /// Three month view
        case total = "3 M"

        var id: Self { self }

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

    /// Defines the available time periods for duration-based statistics
    enum StatsTimeInterval: String, CaseIterable, Identifiable {
        /// Single day interval
        case day = "D"
        /// Week interval
        case week = "W"
        /// Month interval
        case month = "M"
        /// Three month interval
        case total = "3 M"

        var id: Self { self }

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

    /// Defines the main categories of statistics available in the app
    enum StatisticViewType: String, CaseIterable, Identifiable {
        /// Glucose-related statistics including AGP and distributions
        case glucose
        /// Insulin delivery statistics including TDD and bolus distributions
        case insulin
        /// Loop performance and system status statistics
        case looping
        /// Meal-related statistics and correlations
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
