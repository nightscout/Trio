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
        var dailyMealTotalsCache: [Date: (carbs: Double, fat: Double, protein: Double)] = [:]

        // Cache for TDD Stats
        var hourlyTDDStats: [TDDStats] = []
        var dailyTDDStats: [TDDStats] = []
        var tddAveragesCache: [Date: Double] = [:]

        // Cache for Bolus Stats
        var hourlyBolusStats: [BolusStats] = []
        var dailyBolusStats: [BolusStats] = []
        var bolusAveragesCache: [Date: (manual: Double, smb: Double, external: Double)] = [:]
        var bolusTotalsCache: [(Date, total: Double)] = []

        // Cache for Glucose Daily Stats
        var dailyGlucosePercentileStats: [GlucoseDailyPercentileStats] = []
        var glucosePercentileCache: [Date: GlucoseDailyPercentileStats] = [:]
        var dailyGlucoseDistributionStats: [GlucoseDailyDistributionStats] = []
        var glucoseDistributionCache: [Date: GlucoseDailyDistributionStats] = [:]
        var glucoseReadings: [GlucoseStored] = []

        // Selected Duration for Glucose Stats
        var selectedIntervalForGlucoseStats: StatsTimeIntervalWithToday = .today {
            didSet {
                setupGlucoseArray(for: selectedIntervalForGlucoseStats)
            }
        }

        /// The calendar day the `.today` interval reports on.
        ///
        /// That interval used to be today and nothing else. It is now a day picker: today by
        /// default, and any day back to the edge of the stored history. Held once for the whole
        /// screen rather than per tab, so moving through days on the glucose tab and switching
        /// to looping shows the same day rather than silently jumping back to today.
        var selectedStatsDay: Date = Calendar.current.startOfDay(for: Date()) {
            didSet {
                guard !Calendar.current.isDate(oldValue, inSameDayAs: selectedStatsDay) else { return }
                if selectedIntervalForGlucoseStats == .today {
                    setupGlucoseArray(for: selectedIntervalForGlucoseStats)
                }
                if selectedIntervalForLoopStats == .today {
                    setupLoopStatRecords()
                }
            }
        }

        /// The earliest day worth offering: the stats screen itself never looks further back
        /// than `.total`, so nothing before this has data to show.
        var earliestSelectableStatsDay: Date {
            Calendar.current.startOfDay(for: Date().addingTimeInterval(-Self.totalIntervalSeconds))
        }

        /// The window an interval covers.
        ///
        /// Ends at `now` for every interval except a calendar day already in the past, which
        /// ends at its own midnight — otherwise a day selected last week would be reported as
        /// running right up to the present. Single source of truth for the glucose predicate
        /// and both loop-stat fetches, which each used to carry their own copy of this switch.
        func dateRange(for interval: StatsTimeIntervalWithToday) -> (start: Date, end: Date) {
            let now = Date()
            switch interval {
            case .today:
                let start = Calendar.current.startOfDay(for: selectedStatsDay)
                let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
                return (start, min(dayEnd, now))
            case .day:
                return (now.addingTimeInterval(-Self.dayIntervalSeconds), now)
            case .week:
                return (now.addingTimeInterval(-Self.weekIntervalSeconds), now)
            case .month:
                return (now.addingTimeInterval(-Self.monthIntervalSeconds), now)
            case .total:
                return (now.addingTimeInterval(-Self.totalIntervalSeconds), now)
            }
        }

        static let dayIntervalSeconds: TimeInterval = 24 * 3600
        static let weekIntervalSeconds: TimeInterval = 7 * 24 * 3600
        static let monthIntervalSeconds: TimeInterval = 30 * 24 * 3600
        static let totalIntervalSeconds: TimeInterval = 90 * 24 * 3600

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
        var selectedGlucoseChartType: GlucoseChartType = .percentileByTime

        // Selected Insulin Chart Type
        var selectedInsulinChartType: InsulinChartType = .totalDailyDose

        // Selected Looping Chart Type
        var selectedLoopingChartType: LoopingChartType = .loopingPerformance

        // Selected Meal Chart Type
        var selectedMealChartType: MealChartType = .totalMeals

        // Fetching Contexts
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            setupGlucoseArray(for: .today)
            setupTDDStats()
            setupBolusStats()
            setupLoopStatRecords()
            setupMealStats()
            setupGlucoseDailyStats()
            units = settingsManager.settings.units
            eA1cDisplayUnit = settingsManager.settings.eA1cDisplayUnit
            useFPUconversion = settingsManager.settings.useFPUconversion
            timeInRangeType = settingsManager.settings.timeInRangeType
        }

        func setupGlucoseArray(for interval: StatsTimeIntervalWithToday) {
            Task {
                // Load data for current interval (existing code)
                let ids = await fetchGlucose(for: interval)
                await updateGlucoseArray(with: ids)

                // Also ensure we have the full dataset loaded
                if glucoseReadings.isEmpty {
                    let allIds = await fetchGlucose(for: .total)
                    await updateAllGlucoseArray(with: allIds)
                }

                // Calculate hourly stats and glucose range stats asynchronously with fetched glucose IDs
                async let hourlyStats: () = calculateHourlyStatsForGlucoseAreaChart(from: ids)
                async let glucoseRangeStats: () = calculateGlucoseRangeStatsForStackedChart(from: ids)
                _ = await (hourlyStats, glucoseRangeStats)
            }
        }

        func setupGlucoseDailyStats() {
            Task {
                // Get glucose IDs once (using the private fetchGlucose method)
                let allIds = await fetchGlucose(for: .total)

                // Pass the IDs to the implementation in GlucoseStatsSetup.swift
                await setupGlucoseStats(with: allIds)
            }
        }

        private func fetchGlucose(for interval: StatsTimeIntervalWithToday) async -> [NSManagedObjectID] {
            do {
                let context = CoreDataStack.shared.newTaskContext()
                context.name = "StatStateModel.fetchGlucose"

                let predicate: NSPredicate

                switch interval {
                case .day:
                    predicate = NSPredicate.glucoseForStatsDay
                case .week:
                    predicate = NSPredicate.glucoseForStatsWeek
                case .today:
                    // The one interval whose bounds are not "the last N days": it reports on
                    // whichever calendar day the picker is on, so it needs both edges.
                    let range = dateRange(for: interval)
                    predicate = NSPredicate.glucoseForStats(from: range.start, to: range.end)
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

        @MainActor private func updateAllGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? GlucoseStored
                }
                glucoseReadings = glucoseObjects
            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the all glucose array: \(error.localizedDescription)"
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

    /// Defines the available time periods for duration-based statistics including a single
    /// calendar day, which the stats screen's day picker chooses (today by default)
    enum StatsTimeIntervalWithToday: String, CaseIterable, Identifiable {
        /// One calendar day — the one `StateModel.selectedStatsDay` is on, midnight to midnight
        /// (or to now, for today).
        case today
        /// Rolling 24 hours ending now
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
                // Not "Today" any more: this interval reports on whichever day the picker is
                // on. The picker underneath it names the day, so this only has to say what
                // kind of window it is — and it has to be told apart from the rolling 24 h
                // next to it, which is why that one stopped being "D" at the same time.
                return String(localized: "Day", comment: "Stats interval: one calendar day")
            case .day:
                return String(localized: "24 h", comment: "Stats interval: the rolling last 24 hours")
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
