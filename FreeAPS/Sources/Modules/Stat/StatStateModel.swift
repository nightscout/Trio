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
        var hbA1cDisplayUnit: HbA1cDisplayUnit = .percent
        var timeInRangeChartStyle: TimeInRangeChartStyle = .vertical
        var units: GlucoseUnits = .mgdL
        var glucoseFromPersistence: [GlucoseStored] = []
        var loopStatRecords: [LoopStatRecord] = []
        var groupedLoopStats: [LoopStatsByPeriod] = []
        var mealStats: [MealStats] = []

        var selectedDuration: Duration = .Today {
            didSet {
                setupGlucoseArray(for: selectedDuration)
            }
        }

        var selectedDurationForLoopStats: Duration = .Today {
            didSet {
                setupLoopStatRecords()
            }
        }

        var selectedDurationForMealStats: Duration = .Today {
            didSet {
                setupMealStats(for: selectedDurationForMealStats)
            }
        }

        /// TDD-related properties

        /// Total insulin dose for the last 24 hours
        var currentTDD: Decimal = 0

        /// Total insulin dose for yesterday (previous calendar day)
        var ytdTDDValue: Decimal = 0

        /// Average TDD for the selected time period
        var averageTDD: Decimal = 0

        /// Array of daily total doses for the selected period
        var dailyTotalDoses: [TDD] = []

        /// Configuration for TDD display and calculations
        private(set) var tddConfig = TDDConfiguration() {
            didSet {
                if oldValue.requestedDays != tddConfig.requestedDays ||
                    oldValue.endDate != tddConfig.endDate
                {
                    Task {
                        await updateTDDValues()
                    }
                }
            }
        }

        /// Number of days to display in the TDD chart
        var requestedDaysTDD: Int {
            get { tddConfig.requestedDays }
            set { tddConfig.requestedDays = newValue }
        }

        /// End date for the TDD chart
        var requestedEndDayTDD: Date {
            get { tddConfig.endDate }
            set {
                if let adjustedDate = Calendar.current.date(
                    bySettingHour: 23,
                    minute: 59,
                    second: 59,
                    of: newValue
                ) {
                    tddConfig.endDate = adjustedDate
                }
            }
        }

        let context = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
        let determinationFetchContext = CoreDataStack.shared.newTaskContext()
        let loopTaskContext = CoreDataStack.shared.newTaskContext()
        let mealTaskContext = CoreDataStack.shared.newTaskContext()
        let bolusTaskContext = CoreDataStack.shared.newTaskContext()

        enum Duration: String, CaseIterable, Identifiable {
            case Today
            case Day = "D"
            case Week = "W"
            case Month = "M"
            case Total = "3 M."

            var id: Self { self }
        }

        var hourlyStats: [HourlyStats] = []
        var glucoseRangeStats: [GlucoseRangeStats] = []

        var bolusStats: [BolusStats] = []

        override func subscribe() {
            setupGlucoseArray(for: .Today)
            setupTDDs()
            setupLoopStatRecords()
            setupMealStats(for: selectedDurationForMealStats)
            updateBolusStats()
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            hbA1cDisplayUnit = settingsManager.settings.hbA1cDisplayUnit
            timeInRangeChartStyle = settingsManager.settings.timeInRangeChartStyle
        }

        func setupGlucoseArray(for duration: Duration) {
            Task {
                let ids = await fetchGlucose(for: duration)
                await updateGlucoseArray(with: ids)

                // Calculate hourly stats and glucose range stats asynchronously with fetched glucose IDs
                async let hourlyStats: () = calculateHourlyStatsForGlucoseAreaChart(from: ids)
                async let glucoseRangeStats: () = calculateGlucoseRangeStatsForStackedChart(from: ids)
                _ = await (hourlyStats, glucoseRangeStats)
            }
        }

        func setupTDDs() {
            Task {
                await updateTDDValues()
            }
        }

        private func fetchGlucose(for duration: Duration) async -> [NSManagedObjectID] {
            let predicate: NSPredicate

            switch duration {
            case .Day:
                predicate = NSPredicate.glucoseForStatsDay
            case .Week:
                predicate = NSPredicate.glucoseForStatsWeek
            case .Today:
                predicate = NSPredicate.glucoseForStatsToday
            case .Month:
                predicate = NSPredicate.glucoseForStatsMonth
            case .Total:
                predicate = NSPredicate.glucoseForStatsTotal
            }

            let results = await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: GlucoseStored.self,
                onContext: context,
                predicate: predicate,
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

        @MainActor private func updateGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? GlucoseStored
                }
                glucoseFromPersistence = glucoseObjects
            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error.localizedDescription)"
                )
            }
        }
    }
}
