import CoreData
import Foundation
import Observation
import SwiftUI
import Swinject

extension Stat {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        var highLimit: Decimal = 180
        var lowLimit: Decimal = 70
        var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
        var units: GlucoseUnits = .mgdL
        var timeInRangeType: TimeInRangeType = .timeInTightRange
        var useFPUconversion: Bool = false
        var glucoseFromPersistence: [GlucoseStored] = []
        var loopStatRecords: [LoopStatRecord] = []
        var loopStats: [LoopStatsProcessedData] = []
        var groupedLoopStats: [LoopStatsByPeriod] = []
        var bolusStats: [BolusStats] = []
        var hourlyStats: [HourlyStats] = []
        var glucoseRangeStats: [GlucoseRangeStats] = []

        // Cache for Meal Stats
        var hourlyMealStats: [MealStats] = []
        var dailyMealStats: [MealStats] = []
        var dailyAveragesCache: [Date: (carbs: Double, fat: Double, protein: Double)] = [:]

        // Cache for TDD Stats
        var hourlyTDDStats: [TDDStats] = []
        var dailyTDDStats: [TDDStats] = []
        var tddAveragesCache: [Date: Double] = [:]

        // Cache for Bolus Stats
        var hourlyBolusStats: [BolusStats] = []
        var dailyBolusStats: [BolusStats] = []
        var bolusAveragesCache: [Date: (manual: Double, smb: Double, external: Double)] = [:]
        var bolusTotalsCache: [(Date, total: Double)] = []

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
        var selectedIntervalForLoopStats: StatsTimeIntervalWithToday = .today {
            didSet {
                setupLoopStatRecords()
            }
        }

        // Selected Glucose Chart Type
        var selectedGlucoseChartType: GlucoseChartType = .percentile

        // Selected Insulin Chart Type
        var selectedInsulinChartType: InsulinChartType = .totalDailyDose

        // Selected Looping Chart Type
        var selectedLoopingChartType: LoopingChartType = .loopingPerformance

        // Selected Meal Chart Type
        var selectedMealChartType: MealChartType = .totalMeals

        // Fetching Contexts
        let context = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
        let tddTaskContext = CoreDataStack.shared.newTaskContext()
        let loopTaskContext = CoreDataStack.shared.newTaskContext()
        let mealTaskContext = CoreDataStack.shared.newTaskContext()
        let bolusTaskContext = CoreDataStack.shared.newTaskContext()

        override func subscribe() {
            setupGlucoseArray(for: .today)
            setupTDDStats()
            setupBolusStats()
            setupLoopStatRecords()
            setupMealStats()
            units = settingsManager.settings.units
            eA1cDisplayUnit = settingsManager.settings.eA1cDisplayUnit
            useFPUconversion = settingsManager.settings.useFPUconversion
            timeInRangeType = settingsManager.settings.timeInRangeType
        }

        func setupGlucoseArray(for interval: StatsTimeIntervalWithToday) {
            Task {
                let ids = await fetchGlucose(for: interval)
                await updateGlucoseArray(with: ids)

                // Calculate hourly stats and glucose range stats asynchronously with fetched glucose IDs
                async let hourlyStats: () = calculateHourlyStatsForGlucoseAreaChart(from: ids)
                async let glucoseRangeStats: () = calculateGlucoseRangeStatsForStackedChart(from: ids)
                _ = await (hourlyStats, glucoseRangeStats)
            }
        }

        private func fetchGlucose(for interval: StatsTimeIntervalWithToday) async -> [NSManagedObjectID] {
            do {
                let predicate: NSPredicate

                switch interval {
                case .day:
                    predicate = NSPredicate.glucoseForStatsDay
                case .week:
                    predicate = NSPredicate.glucoseForStatsWeek
                case .today:
                    predicate = NSPredicate.glucoseForStatsToday
                case .month:
                    predicate = NSPredicate.glucoseForStatsMonth
                case .total:
                    predicate = NSPredicate.glucoseForStatsTotal
                }

                let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: GlucoseStored.self,
                    onContext: context,
                    predicate: predicate,
                    key: "date",
                    ascending: false,
                    batchSize: 100,
                    propertiesToFetch: ["glucose", "objectID"]
                )

                return try await context.perform {
                    guard let fetchedResults = results as? [[String: Any]] else {
                        throw CoreDataError.fetchError(function: #function, file: #file)
                    }
                    return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Error fetching glucose for stats: \(error)")
                return []
            }
        }

        @MainActor private func updateGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? GlucoseStored
                }
                glucoseFromPersistence = glucoseObjects
            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error)"
                )
            }
        }
    }

    @Observable final class UpdateTimer {
        private var workItem: DispatchWorkItem?

        /// Schedules a delayed update action
        /// - Parameter action: The closure to execute after the delay
        /// Cancels any previously scheduled update before scheduling a new one
        func scheduleUpdate(action: @escaping () -> Void) {
            workItem?.cancel()

            let newWorkItem = DispatchWorkItem {
                action()
            }
            workItem = newWorkItem

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: newWorkItem)
        }
    }
}

// MARK: Stats Types + Enums

extension Stat.StateModel {
    /// Defines the available types of glucose charts
    enum GlucoseChartType: String, CaseIterable {
        /// Ambulatory Glucose Profile showing percentile ranges
        case percentile = "Percentile"
        /// Time-based distribution of glucose ranges
        case distribution = "Distribution"

        var displayName: String {
            switch self {
            case .percentile:
                return String(localized: "Percentile")
            case .distribution:
                return String(localized: "Distribution")
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
