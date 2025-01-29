import CoreData
import Foundation
import Observation
import SwiftUI
import Swinject

extension Stat {
    /// Defines the available types of glucose charts
    enum GlucoseChartType: String, CaseIterable {
        /// Ambulatory Glucose Profile showing percentile ranges
        case percentile = "Percentile"
        /// Time-based distribution of glucose ranges
        case distribution = "Distribution"
    }

    /// Defines the available types of insulin charts
    enum InsulinChartType: String, CaseIterable {
        /// Shows total daily insulin doses
        case totalDailyDose = "Total Daily Dose"
        /// Shows distribution of bolus types
        case bolusDistribution = "Bolus Distribution"
    }

    /// Defines the available types of looping charts
    enum LoopingChartType: String, CaseIterable {
        /// Shows loop completion and success rates
        case loopingPerformance = "Looping Performance"
        /// Shows CGM connection status over time
        case cgmConnectionTrace = "CGM Connection Trace"
        /// Shows Trio pump uptime statistics
        case trioUpTime = "Trio Up-Time"
    }

    /// Defines the available types of meal charts
    enum MealChartType: String, CaseIterable {
        /// Shows total meal statistics
        case totalMeals = "Total Meals"
        /// Shows correlation between meals and glucose excursions
        case mealToHypoHyperDistribution = "Meal to Hypo/Hyper"
    }

    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        var highLimit: Decimal = 180
        var lowLimit: Decimal = 70
        var hbA1cDisplayUnit: HbA1cDisplayUnit = .percent
        var timeInRangeChartStyle: TimeInRangeChartStyle = .vertical
        var units: GlucoseUnits = .mgdL
        var glucoseFromPersistence: [GlucoseStored] = []
        var loopStatRecords: [LoopStatRecord] = []
        var groupedLoopStats: [LoopStatsByPeriod] = []
        var tddStats: [TDD] = []
        var bolusStats: [BolusStats] = []
        var hourlyStats: [HourlyStats] = []
        var glucoseRangeStats: [GlucoseRangeStats] = []

        var glucoseObjectIDs: [NSManagedObjectID] = [] // Cache for NSManagedObjectIDs

        var glucoseScrollPosition = Date() // Scroll position for glucose chart used in updateDisplayedStats()

        // Cache for precalculated stats
        private var dailyStatsCache: [Date: [HourlyStats]] = [:]
        private var weeklyStatsCache: [Date: [HourlyStats]] = [:] // Key: Begin of week
        private var monthlyStatsCache: [Date: [HourlyStats]] = [:] // Key: Begin of month
        private var totalStatsCache: [HourlyStats] = []

        // Cache for GlucoseRangeStats
        private var dailyRangeStatsCache: [Date: [GlucoseRangeStats]] = [:]
        private var weeklyRangeStatsCache: [Date: [GlucoseRangeStats]] = [:]
        private var monthlyRangeStatsCache: [Date: [GlucoseRangeStats]] = [:]
        private var totalRangeStatsCache: [GlucoseRangeStats] = []

        // Cache for Meal Stats
        var hourlyMealStats: [MealStats] = []
        var dailyMealStats: [MealStats] = []
        var dailyAveragesCache: [Date: (carbs: Double, fat: Double, protein: Double)] = [:]

        // Selected Duration for Glucose Stats
        var selectedDurationForGlucoseStats: StatsTimeInterval = .Day {
            didSet {
                Task {
                    await precalculateStats(from: glucoseObjectIDs)
                    await updateDisplayedStats(for: selectedGlucoseChartType)
                }
            }
        }

        // Selected Duration for Insulin Stats
        var selectedDurationForInsulinStats: StatsTimeInterval = .Day

        // Selected Duration for Meal Stats
        var selectedDurationForMealStats: StatsTimeInterval = .Day

        // Selected Duration for Loop Stats
        var selectedDurationForLoopStats: Duration = .Today {
            didSet {
                setupLoopStatRecords()
            }
        }

        // Selected Glucose Chart Type
        var selectedGlucoseChartType: GlucoseChartType = .percentile {
            didSet {
                Task {
                    await updateDisplayedStats(for: selectedGlucoseChartType)
                }
            }
        }

        // Selected Insulin Chart Type
        var selectedInsulinChartType: InsulinChartType = .totalDailyDose

        // Selected Looping Chart Type
        var selectedLoopingChartType: LoopingChartType = .loopingPerformance

        // Selected Meal Chart Type
        var selectedMealChartType: MealChartType = .totalMeals

        // Fetching Contexts
        let context = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
        let determinationFetchContext = CoreDataStack.shared.newTaskContext()
        let loopTaskContext = CoreDataStack.shared.newTaskContext()
        let mealTaskContext = CoreDataStack.shared.newTaskContext()
        let bolusTaskContext = CoreDataStack.shared.newTaskContext()

        /// Defines the available time periods for duration-based statistics
        enum Duration: String, CaseIterable, Identifiable {
            /// Current day
            case Today
            /// Single day view
            case Day = "D"
            /// Week view
            case Week = "W"
            /// Month view
            case Month = "M"
            /// Three month view
            case Total = "3 M"

            var id: Self { self }
        }

        /// Defines the available time intervals for statistical analysis
        enum StatsTimeInterval: String, CaseIterable, Identifiable {
            /// Single day interval
            case Day = "D"
            /// Week interval
            case Week = "W"
            /// Month interval
            case Month = "M"
            /// Three month interval
            case Total = "3 M"

            var id: Self { self }
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

            var title: String {
                switch self {
                case .glucose: return "Glucose"
                case .insulin: return "Insulin"
                case .looping: return "Looping"
                case .meals: return "Meals"
                }
            }
        }

        override func subscribe() {
            setupGlucoseArray()
            setupTDDs()
            setupBolusStats()
            setupLoopStatRecords()
            setupMealStats()
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            hbA1cDisplayUnit = settingsManager.settings.hbA1cDisplayUnit
            timeInRangeChartStyle = settingsManager.settings.timeInRangeChartStyle
        }

        /// Initializes the glucose array and calculates initial statistics
        func setupGlucoseArray() {
            Task {
                let ids = await fetchGlucose()
                await updateGlucoseArray(with: ids)
                await precalculateStats(from: ids)
                await updateDisplayedStats(for: selectedGlucoseChartType)
            }
        }

        /// Fetches glucose readings from CoreData for statistical analysis
        /// - Returns: Array of NSManagedObjectIDs for glucose readings
        /// Fetches only the required properties (glucose and objectID) to optimize performance
        private func fetchGlucose() async -> [NSManagedObjectID] {
            let results = await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: GlucoseStored.self,
                onContext: context,
                predicate: NSPredicate.glucoseForStatsTotal,
                key: "date",
                ascending: false,
                batchSize: 100,
                propertiesToFetch: ["glucose", "objectID"]
            )

            return await context.perform {
                guard let fetchedResults = results as? [[String: Any]] else { return [] }
                return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
            }
        }

        /// Updates the glucose array on the main actor with fetched glucose readings
        /// - Parameter IDs: Array of NSManagedObjectIDs to update from
        /// Also caches the IDs for later use in statistics calculations
        @MainActor private func updateGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? GlucoseStored
                }
                glucoseObjectIDs = IDs // Cache IDs for later use
                glucoseFromPersistence = glucoseObjects
            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error.localizedDescription)"
                )
            }
        }

        /// Precalculates statistics for both chart types (percentile and distribution) based on the selected time interval
        /// - Parameter ids: Array of NSManagedObjectIDs for glucose readings
        /// This function groups glucose values by the selected time interval (day/week/month/total)
        /// and calculates both hourly statistics and range distributions for each group
        private func precalculateStats(from ids: [NSManagedObjectID]) async {
            await context.perform { [self] in
                let glucoseValues = fetchGlucoseValues(from: ids)

                // Group glucose values based on selected time interval
                let groupedValues = groupGlucoseValues(glucoseValues, for: selectedDurationForGlucoseStats)

                // Calculate and cache statistics based on time interval
                switch selectedDurationForGlucoseStats {
                case .Day:
                    dailyStatsCache = calculateStats(for: groupedValues)
                    dailyRangeStatsCache = calculateRangeStats(for: groupedValues)

                case .Week:
                    weeklyStatsCache = calculateStats(for: groupedValues)
                    weeklyRangeStatsCache = calculateRangeStats(for: groupedValues)

                case .Month:
                    monthlyStatsCache = calculateStats(for: groupedValues)
                    monthlyRangeStatsCache = calculateRangeStats(for: groupedValues)

                case .Total:
                    totalStatsCache = calculateHourlyStats(from: ids)
                    totalRangeStatsCache = calculateGlucoseRangeStats(from: ids)
                }
            }
        }

        /// Groups glucose values based on the selected time interval
        /// - Parameters:
        ///   - values: Array of glucose readings
        ///   - interval: Selected time interval (day/week/month)
        /// - Returns: Dictionary with date as key and array of glucose readings as value
        private func groupGlucoseValues(
            _ values: [GlucoseStored],
            for interval: StatsTimeInterval
        ) -> [Date: [GlucoseStored]] {
            let calendar = Calendar.current

            switch interval {
            case .Day:
                return Dictionary(grouping: values) {
                    calendar.startOfDay(for: $0.date ?? Date())
                }
            case .Week:
                return Dictionary(grouping: values) {
                    calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date ?? Date()))!
                }
            case .Month:
                return Dictionary(grouping: values) {
                    calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date ?? Date()))!
                }
            case .Total:
                return [:] // Not used for total stats
            }
        }

        /// Helper function to safely fetch glucose values from CoreData
        /// - Parameter ids: Array of NSManagedObjectIDs
        /// - Returns: Array of GlucoseStored objects
        func fetchGlucoseValues(from ids: [NSManagedObjectID]) -> [GlucoseStored] {
            ids.compactMap { id -> GlucoseStored? in
                do {
                    return try context.existingObject(with: id) as? GlucoseStored
                } catch let error as NSError {
                    debugPrint("\(DebuggingIdentifiers.failed) Error fetching glucose: \(error.userInfo)")
                    return nil
                }
            }
        }

        /// Updates the displayed statistics based on the selected chart type and time interval
        /// - Parameter chartType: The type of chart being displayed (percentile or distribution)
        @MainActor func updateDisplayedStats(for chartType: GlucoseChartType) {
            let calendar = Calendar.current

            // Get the appropriate start date based on the selected time interval
            let startDate: Date = {
                switch selectedDurationForGlucoseStats {
                case .Day:
                    return calendar.startOfDay(for: glucoseScrollPosition)
                case .Week:
                    return calendar
                        .date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: glucoseScrollPosition))!
                case .Month:
                    return calendar.date(from: calendar.dateComponents([.year, .month], from: glucoseScrollPosition))!
                case .Total:
                    return glucoseScrollPosition
                }
            }()

            // Update the appropriate stats based on chart type
            switch (selectedDurationForGlucoseStats, chartType) {
            case (.Day, .percentile):
                hourlyStats = dailyStatsCache[startDate] ?? []
            case (.Day, .distribution):
                glucoseRangeStats = dailyRangeStatsCache[startDate] ?? []
            case (.Week, .percentile):
                hourlyStats = weeklyStatsCache[startDate] ?? []
            case (.Week, .distribution):
                glucoseRangeStats = weeklyRangeStatsCache[startDate] ?? []
            case (.Month, .percentile):
                hourlyStats = monthlyStatsCache[startDate] ?? []
            case (.Month, .distribution):
                glucoseRangeStats = monthlyRangeStatsCache[startDate] ?? []
            case (.Total, .percentile):
                hourlyStats = totalStatsCache
            case (.Total, .distribution):
                glucoseRangeStats = totalRangeStatsCache
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: newWorkItem)
        }
    }
}
