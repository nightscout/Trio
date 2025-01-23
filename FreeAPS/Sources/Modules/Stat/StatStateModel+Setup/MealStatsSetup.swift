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
    func setupMealStats(for duration: Duration) {
        Task {
            let stats = await fetchMealStats(for: duration)
            await MainActor.run {
                self.mealStats = stats
            }
        }
    }

    /// Fetches and processes meal statistics for a specific duration
    /// - Parameter duration: The time period to fetch records for (Today, 24h, 7 Days, 30 Days, or All)
    /// - Returns: Array of MealStats containing daily meal statistics, sorted by date
    private func fetchMealStats(for duration: Duration) async -> [MealStats] {
        let now = Date()
        let calendar = Calendar.current

        // Determine start date based on selected duration
        // For Today and 24h, we show 3 days of data for better context
        // For other durations, we fetch the respective time period
        let startDate: Date
        switch duration {
        case .Today:
            startDate = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))!
        case .Day:
            startDate = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))!
        case .Week:
            startDate = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
        case .Month:
            startDate = calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: now))!
        case .Total:
            startDate = calendar.date(byAdding: .month, value: -3, to: calendar.startOfDay(for: now))!
        }

        // Fetch CarbEntryStored entries from Core Data
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: mealTaskContext,
            predicate: NSPredicate(format: "date >= %@", startDate as NSDate),
            key: "date",
            ascending: false,
            batchSize: 100
        )

        return await mealTaskContext.perform {
            // Safely unwrap the fetched results, return empty array if nil
            guard let fetchedResults = results as? [CarbEntryStored] else { return [] }

            // Group entries by day using calendar's startOfDay
            // This ensures all entries within the same day are grouped together
            // regardless of their specific time
            let groupedEntries = Dictionary(grouping: fetchedResults) { entry in
                calendar.startOfDay(for: entry.date ?? Date())
            }

            // Create array of all dates in the range
            // This ensures we have entries for every day in the range,
            // even if there are no meal entries for some days
            var dates: [Date] = []
            var currentDate = startDate
            while currentDate <= now {
                dates.append(calendar.startOfDay(for: currentDate))
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }

            // Calculate statistics for each day
            // For days without entries, all values will be 0
            return dates.map { date in
                let entries = groupedEntries[date, default: []]

                // Sum up macronutrients for the day
                // Each reduce operation calculates the total for one macronutrient
                let carbsTotal = entries.reduce(0.0) { $0 + $1.carbs } // Total carbs in grams
                let fatTotal = entries.reduce(0.0) { $0 + $1.fat } // Total fat in grams
                let proteinTotal = entries.reduce(0.0) { $0 + $1.protein } // Total protein in grams

                return MealStats(
                    date: date,
                    carbs: carbsTotal,
                    fat: fatTotal,
                    protein: proteinTotal
                )
            }.sorted { $0.date < $1.date } // Sort results by date in ascending order
        }
    }
}
