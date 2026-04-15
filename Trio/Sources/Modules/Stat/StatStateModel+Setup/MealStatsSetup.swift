import CoreData
import Foundation

/// Represents statistical data about meal macronutrients for a specific day
struct MealStats: Identifiable {
    let id = UUID()
    /// The date representing this time period
    let date: Date
    /// Total carbohydrates in grams
    let carbs: Double
    /// Total fat in grams
    let fat: Double
    /// Total protein in grams
    let protein: Double
}

extension Stat.StateModel {
    /// Sets up meal statistics by fetching and processing meal data
    ///
    /// This function:
    /// 1. Fetches hourly and daily meal statistics asynchronously
    /// 2. Updates the state model with the fetched statistics on the main actor
    /// 3. Calculates and caches initial daily averages
    func setupMealStats() {
        Task {
            do {
                let (hourly, daily) = try await fetchMealStats()

                await MainActor.run {
                    self.hourlyMealStats = hourly
                    self.dailyMealStats = daily
                }

                // Initially calculate and cache daily averages
                await calculateAndCacheDailyAverages()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch meal stats: \(error)")
            }
        }
    }

    /// Fetches and processes meal statistics from Core Data
    /// - Returns: A tuple containing hourly and daily meal statistics arrays
    ///
    /// This function:
    /// 1. Fetches carbohydrate entries from Core Data
    /// 2. Groups entries by hour and day
    /// 3. Calculates total macronutrients for each time period
    /// 4. Returns the processed statistics as (hourly: [MealStats], daily: [MealStats])
    private func fetchMealStats() async throws -> (hourly: [MealStats], daily: [MealStats]) {
        // Fetch CarbEntryStored entries from Core Data
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: mealTaskContext,
            predicate: NSPredicate.carbsForStats,
            key: "date",
            ascending: true,
            batchSize: 100
        )

        return await mealTaskContext.perform {
            // Safely unwrap the fetched results, return empty arrays if nil
            guard let fetchedResults = results as? [CarbEntryStored] else { return ([], []) }

            let calendar = Calendar.current

            // Group entries by hour for hourly statistics
            let now = Date()
            let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: now) ?? now

            let hourlyGrouped = Dictionary(grouping: fetchedResults.filter { entry in
                guard let date = entry.date else { return false }
                return date >= twentyDaysAgo && date <= now
            }) { entry in
                let components = calendar.dateComponents([.year, .month, .day, .hour], from: entry.date ?? Date())
                return calendar.date(from: components) ?? Date()
            }

            // Group entries by day for daily statistics
            let dailyGrouped = Dictionary(grouping: fetchedResults) { entry in
                calendar.startOfDay(for: entry.date ?? Date())
            }

            // Calculate statistics for each hour
            let hourlyStats = hourlyGrouped.keys.sorted().map { timePoint in
                let entries = hourlyGrouped[timePoint, default: []]
                return MealStats(
                    date: timePoint,
                    carbs: entries.reduce(0.0) { $0 + $1.carbs },
                    fat: entries.reduce(0.0) { $0 + $1.fat },
                    protein: entries.reduce(0.0) { $0 + $1.protein }
                )
            }

            // Calculate statistics for each day
            let dailyStats = dailyGrouped.keys.sorted().map { timePoint in
                let entries = dailyGrouped[timePoint, default: []]
                return MealStats(
                    date: timePoint,
                    carbs: entries.reduce(0.0) { $0 + $1.carbs },
                    fat: entries.reduce(0.0) { $0 + $1.fat },
                    protein: entries.reduce(0.0) { $0 + $1.protein }
                )
            }

            return (hourlyStats, dailyStats)
        }
    }

    /// Calculates and caches the daily averages of macronutrients
    ///
    /// This function:
    /// 1. Groups meal statistics by day
    /// 2. Calculates average carbs, fat and protein for each day
    /// 3. Caches the results for later use
    ///
    /// This only needs to be called once during subscribe.
    private func calculateAndCacheDailyAverages() async {
        let calendar = Calendar.current

        // Calculate averages in context
        let dailyAverages = await mealTaskContext.perform { [dailyMealStats] in
            // Group by days
            let groupedByDay = Dictionary(grouping: dailyMealStats) { stat in
                calendar.startOfDay(for: stat.date)
            }

            // Calculate averages for each day
            var averages: [Date: (Double, Double, Double)] = [:]
            for (day, stats) in groupedByDay {
                let total = stats.reduce((0.0, 0.0, 0.0)) { acc, stat in
                    (acc.0 + stat.carbs, acc.1 + stat.fat, acc.2 + stat.protein)
                }
                let count = Double(stats.count)
                averages[day] = (total.0 / count, total.1 / count, total.2 / count)
            }
            return averages
        }

        // Update cache on main thread
        await MainActor.run {
            self.dailyAveragesCache = dailyAverages
        }
    }

    /// Returns the average macronutrient values for the given date range from the cache
    /// - Parameter range: A tuple containing the start and end dates to get averages for
    /// - Returns: A tuple containing the average carbs, fat and protein values for the date range
    func getCachedMealAverages(for range: (start: Date, end: Date)) -> (carbs: Double, fat: Double, protein: Double) {
        return calculateAveragesForDateRange(from: range.start, to: range.end)
    }

    /// Calculates the average macronutrient values for a given date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: A tuple containing the average carbs, fat and protein values for the date range
    func calculateAveragesForDateRange(from startDate: Date, to endDate: Date) -> (carbs: Double, fat: Double, protein: Double) {
        // Filter cached values to only include those within the date range
        let relevantStats = dailyAveragesCache.filter { date, _ in
            date >= startDate && date <= endDate
        }

        // Return zeros if no data exists for the range
        guard !relevantStats.isEmpty else { return (0, 0, 0) }

        // Calculate total macronutrients across all days
        let total = relevantStats.values.reduce((0.0, 0.0, 0.0)) { acc, avg in
            (acc.0 + avg.0, acc.1 + avg.1, acc.2 + avg.2)
        }

        // Calculate averages by dividing totals by number of days
        let count = Double(relevantStats.count)

        return (total.0 / count, total.1 / count, total.2 / count)
    }
}
