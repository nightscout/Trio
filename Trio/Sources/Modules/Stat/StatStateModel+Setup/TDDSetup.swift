import CoreData
import Foundation

/// Represents statistical data about Total Daily Dose for a specific time period
struct TDDStats: Identifiable {
    let id = UUID()
    /// The date representing this time period
    let date: Date
    /// Total insulin in units
    let amount: Double
}

extension Stat.StateModel {
    /// Sets up TDD statistics by fetching and processing insulin data
    func setupTDDStats() {
        Task {
            do {
                let (hourly, daily) = try await fetchTDDStats()

                await MainActor.run {
                    self.hourlyTDDStats = hourly
                    self.dailyTDDStats = daily
                }

                // Initially calculate and cache daily averages
                await calculateAndCacheTDDAverages()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed fetching TDD stats: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches and processes Total Daily Dose (TDD) statistics from CoreData
    /// - Returns: A tuple containing hourly and daily TDD statistics arrays
    /// - Note: Processes both hourly statistics for the last 10 days and complete daily statistics
    private func fetchTDDStats() async throws -> (hourly: [TDDStats], daily: [TDDStats]) {
        // Fetch temp basal records from CoreData
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempBasalStored.self,
            onContext: tddTaskContext,
            predicate: NSPredicate.pumpHistoryForStats,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        var hourlyStats: [TDDStats] = []
        var dailyStats: [TDDStats] = []

        await tddTaskContext.perform {
            guard let fetchedResults = results as? [TempBasalStored] else {
                return
            }

            let calendar = Calendar.current

            // Calculate date range for hourly statistics (last 10 days)
            // TODO: - Introduce paging to also be able to show complete history
            let now = Date()
            let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now

            // Group entries by hour for hourly statistics, filtering for last 10 days only
            let hourlyGrouped = Dictionary(grouping: fetchedResults.filter { entry in
                guard let date = entry.pumpEvent?.timestamp else { return false }
                return date >= tenDaysAgo && date <= now
            }) { entry in
                // Create date components for hour-level grouping
                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour],
                    from: entry.pumpEvent?.timestamp ?? Date()
                )
                return calendar.date(from: components) ?? Date()
            }

            // Group entries by day for complete daily statistics
            let dailyGrouped = Dictionary(grouping: fetchedResults) { entry in
                calendar.startOfDay(for: entry.pumpEvent?.timestamp ?? Date())
            }

            // Process hourly statistics
            hourlyStats = hourlyGrouped.keys.sorted().map { timePoint in
                let entries = hourlyGrouped[timePoint, default: []]
                // Calculate total insulin for each hour
                return TDDStats(
                    date: timePoint,
                    amount: entries.reduce(0.0) { sum, entry in
                        sum + (entry.rate?.doubleValue ?? 0) * Double(entry.duration) / 60.0
                    }
                )
            }

            // Process daily statistics
            dailyStats = dailyGrouped.keys.sorted().map { timePoint in
                let entries = dailyGrouped[timePoint, default: []]
                // Calculate total insulin for each day
                return TDDStats(
                    date: timePoint,
                    amount: entries.reduce(0.0) { sum, entry in
                        sum + (entry.rate?.doubleValue ?? 0) * Double(entry.duration) / 60.0
                    }
                )
            }
        }

        return (hourlyStats, dailyStats)
    }

    /// Calculates and caches the daily averages of Total Daily Dose (TDD) insulin values
    /// - Note: This function runs asynchronously and updates the tddAveragesCache on the main actor
    private func calculateAndCacheTDDAverages() async {
        // Get calendar for date calculations
        let calendar = Calendar.current

        // Calculate daily averages on background context
        let dailyAverages = await tddTaskContext.perform { [dailyTDDStats] in
            // Group TDD stats by calendar day
            let groupedByDay = Dictionary(grouping: dailyTDDStats) { stat in
                calendar.startOfDay(for: stat.date)
            }

            // Calculate average TDD for each day
            var averages: [Date: Double] = [:]
            for (day, stats) in groupedByDay {
                // Sum up all TDD values for the day
                let total = stats.reduce(0.0) { $0 + $1.amount }
                let count = Double(stats.count)
                // Store average in dictionary
                averages[day] = total / count
            }
            return averages
        }

        // Update cache on main actor
        await MainActor.run {
            self.tddAveragesCache = dailyAverages
        }
    }

    /// Gets the cached average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameter range: A tuple containing the start and end dates to get averages for
    /// - Returns: The average TDD in units for the specified date range
    func getCachedTDDAverages(for range: (start: Date, end: Date)) -> Double {
        // Calculate and return the TDD averages for the given date range using cached values
        calculateTDDAveragesForDateRange(from: range.start, to: range.end)
    }

    /// Calculates the average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: The average TDD in units for the specified date range. Returns 0.0 if no data exists.
    private func calculateTDDAveragesForDateRange(from startDate: Date, to endDate: Date) -> Double {
        // Filter cached TDD values to only include those within the date range
        let relevantStats = tddAveragesCache.filter { date, _ in
            date >= startDate && date <= endDate
        }

        // Return 0 if no data exists for the specified range
        guard !relevantStats.isEmpty else { return 0.0 }

        // Calculate total TDD by summing all values
        let total = relevantStats.values.reduce(0.0, +)
        // Convert count to Double for floating point division
        let count = Double(relevantStats.count)

        // Return average TDD
        return total / count
    }
}
