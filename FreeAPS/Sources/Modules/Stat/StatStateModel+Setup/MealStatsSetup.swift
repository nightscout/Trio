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

            // Group entries by day or hour depending on selected duration
            let groupedEntries = Dictionary(grouping: fetchedResults) { entry in
                if self.selectedDurationForMealStats == .Day {
                    // For Day view, group by hour
                    let components = calendar.dateComponents([.year, .month, .day, .hour], from: entry.date ?? Date())
                    return calendar.date(from: components) ?? Date()
                } else {
                    // For other views, group by day
                    return calendar.startOfDay(for: entry.date ?? Date())
                }
            }

            // Get all unique dates/hours from the entries
            let timePoints = groupedEntries.keys.sorted()

            // Calculate statistics for each time point
            return timePoints.map { timePoint in
                let entries = groupedEntries[timePoint, default: []]

                let carbsTotal = entries.reduce(0.0) { $0 + $1.carbs }
                let fatTotal = entries.reduce(0.0) { $0 + $1.fat }
                let proteinTotal = entries.reduce(0.0) { $0 + $1.protein }

                return MealStats(
                    date: timePoint,
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
        let filteredStats = mealStats.filter { stat in
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
