import CoreData
import Foundation

/// Represents statistical data about meal macronutrients for a specific day
struct MealStats: Identifiable {
    var id: Date { date }
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
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch meal stats: \(error)")
            }
        }
    }

    private static func makeStats(date: Date, entries: [(date: Date, entry: CarbEntryStored)]) -> MealStats {
        let sums = entries.reduce((carbs: 0.0, fat: 0.0, protein: 0.0)) { acc, item in
            (acc.carbs + item.entry.carbs, acc.fat + item.entry.fat, acc.protein + item.entry.protein)
        }
        return MealStats(date: date, carbs: sums.carbs, fat: sums.fat, protein: sums.protein)
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
        let mealTaskContext = CoreDataStack.shared.newTaskContext()
        mealTaskContext.name = "StatStateModel.fetchMealStats"

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
            let twentyDaysAgo = calendar.date(byAdding: .day, value: -StatChartUtils.hourlyWindowDays, to: now)!

            let validEntries = fetchedResults.compactMap { entry -> (date: Date, entry: CarbEntryStored)? in
                guard let date = entry.date else { return nil }
                return (date, entry)
            }

            let lastTwentyDays = validEntries.filter { $0.date >= twentyDaysAgo && $0.date <= now }

            let hourlyGrouped = Dictionary(grouping: lastTwentyDays) {
                calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: $0.date))!
            }
            let dailyGrouped = Dictionary(grouping: validEntries) { calendar.startOfDay(for: $0.date) }

            // Calculate statistics for each hour
            let hourlyStats = hourlyGrouped.sorted { $0.key < $1.key }.map {
                Self.makeStats(date: $0.key, entries: $0.value)
            }

            let dailyStats = dailyGrouped.sorted { $0.key < $1.key }.map {
                Self.makeStats(date: $0.key, entries: $0.value)
            }

            return (hourlyStats, dailyStats)
        }
    }

    /// Calculates the average macronutrient values for a given date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: A tuple containing the average carbs, fat and protein values for the date range
    func calculateMealAverages(for range: (start: Date, end: Date)) -> (carbs: Double, fat: Double, protein: Double) {
        let relevantStats = dailyMealStats.filter { stat in
            StatChartUtils.isStatInRange(
                calendar.startOfDay(for: stat.date),
                in: range
            )
        }

        // Return zeros if no data exists for the range
        guard !relevantStats.isEmpty else { return (0, 0, 0) }

        // Calculate total macronutrients across all days
        let sums = relevantStats.reduce((0.0, 0.0, 0.0)) { acc, day in
            (acc.0 + day.carbs, acc.1 + day.fat, acc.2 + day.protein)
        }

        // Calculate averages by dividing totals by number of days
        let count = Double(relevantStats.count)

        return (sums.0 / count, sums.1 / count, sums.2 / count)
    }

    func calculateMealTotals(for range: (start: Date, end: Date)) -> (carbs: Double, fat: Double, protein: Double) {
        let relevantStats = hourlyMealStats.filter { stat in
            StatChartUtils.isStatInRange(
                stat.date,
                in: range
            )
        }

        let sums = relevantStats.reduce((0.0, 0.0, 0.0)) { acc, hour in
            (acc.0 + hour.carbs, acc.1 + hour.fat, acc.2 + hour.protein)
        }

        return sums
    }
}
