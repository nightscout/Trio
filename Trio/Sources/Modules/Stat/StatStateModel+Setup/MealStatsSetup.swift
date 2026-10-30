import CoreData
import Foundation

struct MealStats: Identifiable {
    var id: Date { date }
    let date: Date
    let carbs: Double
    let fat: Double
    let protein: Double
}

extension Stat.StateModel {
    func setupMealStats() {
        Task {
            do {
                let (hourly, daily) = try await fetchMealStats()

                await MainActor.run {
                    self.hourlyMealStats = hourly
                    self.dailyMealStats = daily
                }
            } catch {
                warning(.ui, "Fetching meal statistics failed", error: error)
            }
        }
    }

    private static func makeMealStats(date: Date, entries: [(date: Date, entry: CarbEntryStored)]) -> MealStats {
        let sums = entries.reduce((carbs: 0.0, fat: 0.0, protein: 0.0)) { acc, item in
            (acc.carbs + item.entry.carbs, acc.fat + item.entry.fat, acc.protein + item.entry.protein)
        }
        return MealStats(date: date, carbs: sums.carbs, fat: sums.fat, protein: sums.protein)
    }

    private func fetchMealStats() async throws -> (hourly: [MealStats], daily: [MealStats]) {
        let mealTaskContext = CoreDataStack.shared.newTaskContext()
        mealTaskContext.name = "StatStateModel.fetchMealStats"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: mealTaskContext,
            predicate: NSPredicate.carbsForStats,
            key: "date",
            ascending: true,
            batchSize: 100
        )

        return await mealTaskContext.perform {
            guard let fetchedResults = results as? [CarbEntryStored] else { return ([], []) }

            let validEntries = fetchedResults.compactMap { entry -> (date: Date, entry: CarbEntryStored)? in
                guard let date = entry.date else { return nil }
                return (date, entry)
            }
            let calendar = Calendar.current
            let (twentyDaysAgo, now) = StatChartUtils.hourlyWindow(calendar: calendar)
            let lastTwentyDays = validEntries.filter { $0.date >= twentyDaysAgo && $0.date <= now }

            let hourlyGrouped = Dictionary(grouping: lastTwentyDays) {
                calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: $0.date))!
            }
            let dailyGrouped = Dictionary(grouping: validEntries) { calendar.startOfDay(for: $0.date) }

            let hourlyStats = hourlyGrouped.sorted { $0.key < $1.key }.map {
                Self.makeMealStats(date: $0.key, entries: $0.value)
            }

            let dailyStats = dailyGrouped.sorted { $0.key < $1.key }.map {
                Self.makeMealStats(date: $0.key, entries: $0.value)
            }

            return (hourlyStats, dailyStats)
        }
    }

    func calculateMealStats(for range: (start: Date, end: Date)) -> (carbs: Double, fat: Double, protein: Double) {
        let isDay = selectedIntervalForMealStats == .day
        let stats = isDay ? hourlyMealStats : dailyMealStats
        let relevantStats = stats.filter { StatChartUtils.isStatInRange($0.date, in: range) }

        guard !relevantStats.isEmpty else { return (0, 0, 0) }

        let sums = relevantStats.reduce((carbs: 0.0, fat: 0.0, protein: 0.0)) { acc, entry in
            (acc.carbs + entry.carbs, acc.fat + entry.fat, acc.protein + entry.protein)
        }
        // Day view sums hourly buckets into a daily total and longer spans average across days.
        let divisor = isDay ? 1.0 : Double(relevantStats.count)
        return (sums.carbs / divisor, sums.fat / divisor, sums.protein / divisor)
    }
}
