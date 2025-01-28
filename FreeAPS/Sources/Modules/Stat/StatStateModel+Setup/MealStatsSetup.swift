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
    /// Initiates the process of fetching and processing meal statistics
    /// - Parameter duration: The time period to fetch records for
    func setupMealStats() {
        Task {
            let stats = await fetchMealStats()
            await MainActor.run {
                self.mealStats = stats
            }
        }
    }

    /// Fetches and processes meal statistics for a specific duration
    /// - Parameter duration: The time period to fetch records for (Today, 24h, 7 Days, 30 Days, or All)
    /// - Returns: Array of MealStats containing daily meal statistics, sorted by date
    private func fetchMealStats() async -> [MealStats] {
        // Fetch CarbEntryStored entries from Core Data
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: mealTaskContext,
            predicate: NSPredicate.carbsForStats,
            key: "date",
            ascending: true,
            batchSize: 100
        )

        return await mealTaskContext.perform {
            // Safely unwrap the fetched results, return empty array if nil
            guard let fetchedResults = results as? [CarbEntryStored] else { return [] }

            let calendar = Calendar.current

            // Group entries by day using calendar's startOfDay
            let groupedEntries = Dictionary(grouping: fetchedResults) { entry in
                calendar.startOfDay(for: entry.date ?? Date())
            }

            // Get all unique dates from the entries - they'll already be sorted
            let dates = groupedEntries.keys.sorted()

            // Calculate statistics for each day
            return dates.map { date in
                let entries = groupedEntries[date, default: []]

                // Sum up macronutrients for the day
                let carbsTotal = entries.reduce(0.0) { $0 + $1.carbs }
                let fatTotal = entries.reduce(0.0) { $0 + $1.fat }
                let proteinTotal = entries.reduce(0.0) { $0 + $1.protein }

                return MealStats(
                    date: date,
                    carbs: carbsTotal,
                    fat: fatTotal,
                    protein: proteinTotal
                )
            }
        }
    }

    func calculateAverageMealStats(
        from startDate: Date,
        to endDate: Date
    ) async -> (carbs: Double, fat: Double, protein: Double) {
        let filteredStats = self.mealStats.filter { stat in
            stat.date >= startDate && stat.date <= endDate
        }

        guard !filteredStats.isEmpty else { return (0, 0, 0) }

        let totalCarbs = filteredStats.reduce(0.0) { $0 + $1.carbs }
        let totalFat = filteredStats.reduce(0.0) { $0 + $1.fat }
        let totalProtein = filteredStats.reduce(0.0) { $0 + $1.protein }
        let count = Double(filteredStats.count)

        return (
            carbs: totalCarbs / count,
            fat: totalFat / count,
            protein: totalProtein / count
        )
    }
}
