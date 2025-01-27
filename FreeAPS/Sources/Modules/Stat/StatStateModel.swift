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
        var tddStats: [TDD] = []
        var selectedDurationForGlucoseStats: Duration = .Today {
            didSet {
                setupGlucoseArray(for: selectedDurationForGlucoseStats)
            }
        }

        var selectedDurationForInsulinStats: StatsTimeInterval = .Day

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
            case Total = "3 M"

            var id: Self { self }
        }

        enum StatsTimeInterval: String, CaseIterable, Identifiable {
            case Day = "D"
            case Week = "W"
            case Month = "M"
            case Total = "3 M"

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
                let tddStats = await fetchAndMapDeterminations()
                await MainActor.run {
                    self.tddStats = tddStats
                }
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

        var averageTDD: Decimal {
            let calendar = Calendar.current
            let now = Date()

            // Filter TDDs based on selected time frame
            let filteredTDDs: [TDD] = tddStats.filter { tdd in
                guard let timestamp = tdd.timestamp else { return false }

                switch selectedDurationForInsulinStats {
                case .Day:
                    // Last 3 days
                    let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
                    return timestamp >= threeDaysAgo
                case .Week:
                    // Last week
                    let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
                    return timestamp >= weekAgo
                case .Month:
                    // Last month
                    let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
                    return timestamp >= monthAgo
                case .Total:
                    // Last 3 months
                    let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
                    return timestamp >= threeMonthsAgo
                }
            }

            let sum = filteredTDDs.reduce(Decimal.zero) { $0 + ($1.totalDailyDose ?? 0) }
            return filteredTDDs.isEmpty ? 0 : sum / Decimal(filteredTDDs.count)
        }

        func calculateAverageTDD(from startDate: Date, to endDate: Date) -> Decimal {
            let filteredTDDs = tddStats.filter { tdd in
                guard let timestamp = tdd.timestamp else { return false }
                return timestamp >= startDate && timestamp <= endDate
            }

            let sum = filteredTDDs.reduce(Decimal.zero) { $0 + ($1.totalDailyDose ?? 0) }
            return filteredTDDs.isEmpty ? 0 : sum / Decimal(filteredTDDs.count)
        }
    }
}
