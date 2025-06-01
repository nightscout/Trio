import CoreData
import Foundation

/// Represents statistical data about bolus insulin for a specific time period
struct BolusStats: Identifiable {
    let id = UUID()
    /// The date representing this time period
    let date: Date
    /// Total manual bolus insulin in units
    let manualBolus: Double
    /// Total SMB insulin in units
    let smb: Double
    /// Total external bolus insulin in units
    let external: Double
}

extension Stat.StateModel {
    /// Sets up bolus statistics by fetching and processing bolus data
    ///
    /// This function:
    /// 1. Fetches hourly and daily bolus statistics asynchronously
    /// 2. Updates the state model with the fetched statistics on the main actor
    /// 3. Calculates and caches initial daily averages
    func setupBolusStats() {
        Task {
            do {
                let (hourly, daily) = try await fetchBolusStats()

                await MainActor.run {
                    self.hourlyBolusStats = hourly
                    self.dailyBolusStats = daily
                }

                // Initially calculate and cache daily averages
                await calculateAndCacheBolusAveragesAndTotals()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to setup bolus stats: \(error)")
            }
        }
    }

    /// Fetches and processes bolus statistics from Core Data
    /// - Returns: A tuple containing hourly and daily bolus statistics arrays
    ///
    /// This function:
    /// 1. Fetches bolus entries from Core Data
    /// 2. Groups entries by hour and day
    /// 3. Calculates total insulin for each time period
    /// 4. Returns the processed statistics as (hourly: [BolusStats], daily: [BolusStats])
    private func fetchBolusStats() async throws -> (hourly: [BolusStats], daily: [BolusStats]) {
        // Fetch PumpEventStored entries from Core Data
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: bolusTaskContext,
            predicate: NSPredicate.pumpHistoryForStats,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        // Variables to hold the results
        var hourlyStats: [BolusStats] = []
        var dailyStats: [BolusStats] = []

        // Process CoreData results within the context's thread
        await bolusTaskContext.perform {
            guard let fetchedResults = results as? [BolusStored] else {
                return
            }

            let calendar = Calendar.current

            // Group entries by hour for hourly statistics
            let now = Date()
            let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: now) ?? now

            let hourlyGrouped = Dictionary(grouping: fetchedResults.filter { entry in
                guard let date = entry.pumpEvent?.timestamp else { return false }
                return date >= twentyDaysAgo && date <= now
            }) { entry in
                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour],
                    from: entry.pumpEvent?.timestamp ?? Date()
                )
                return calendar.date(from: components) ?? Date()
            }

            // Group entries by day for daily statistics
            let dailyGrouped = Dictionary(grouping: fetchedResults) { entry in
                calendar.startOfDay(for: entry.pumpEvent?.timestamp ?? Date())
            }

            // Process hourly stats
            hourlyStats = hourlyGrouped.keys.sorted().map { timePoint in
                let entries = hourlyGrouped[timePoint, default: []]
                return BolusStats(
                    date: timePoint,
                    manualBolus: entries.reduce(0.0) { sum, entry in
                        if !entry.isSMB, !entry.isExternal {
                            return sum + (entry.amount?.doubleValue ?? 0)
                        }
                        return sum
                    },
                    smb: entries.reduce(0.0) { sum, entry in
                        if entry.isSMB {
                            return sum + (entry.amount?.doubleValue ?? 0)
                        }
                        return sum
                    },
                    external: entries.reduce(0.0) { sum, entry in
                        if entry.isExternal {
                            return sum + (entry.amount?.doubleValue ?? 0)
                        }
                        return sum
                    }
                )
            }

            // Process daily stats
            dailyStats = dailyGrouped.keys.sorted().map { timePoint in
                let entries = dailyGrouped[timePoint, default: []]
                return BolusStats(
                    date: timePoint,
                    manualBolus: entries.reduce(0.0) { sum, entry in
                        if !entry.isSMB, !entry.isExternal {
                            return sum + (entry.amount?.doubleValue ?? 0)
                        }
                        return sum
                    },
                    smb: entries.reduce(0.0) { sum, entry in
                        if entry.isSMB {
                            return sum + (entry.amount?.doubleValue ?? 0)
                        }
                        return sum
                    },
                    external: entries.reduce(0.0) { sum, entry in
                        if entry.isExternal {
                            return sum + (entry.amount?.doubleValue ?? 0)
                        }
                        return sum
                    }
                )
            }
        }

        return (hourlyStats, dailyStats)
    }

    /// Calculates and caches the daily averages of bolus insulin
    ///
    /// This function:
    /// 1. Groups bolus statistics by day
    /// 2. Calculates average total, carb and correction bolus for each day
    /// 3. Caches the results for later use
    ///
    /// This only needs to be called once during subscribe.
    private func calculateAndCacheBolusAveragesAndTotals() async {
        let calendar = Calendar.current

        // Calculate averages in context
        let dailyAverages = await bolusTaskContext.perform { [dailyBolusStats] in
            // Group by days
            let groupedByDay = Dictionary(grouping: dailyBolusStats) { stat in
                calendar.startOfDay(for: stat.date)
            }

            // Calculate averages for each day
            var averages: [Date: (Double, Double, Double)] = [:]
            for (day, stats) in groupedByDay {
                let total = stats.reduce((0.0, 0.0, 0.0)) { acc, stat in
                    (acc.0 + stat.manualBolus, acc.1 + stat.smb, acc.2 + stat.external)
                }
                let count = Double(stats.count)
                averages[day] = (total.0 / count, total.1 / count, total.2 / count)
            }
            return averages
        }

        // Calculate averages in context
        let dailyTotals = await bolusTaskContext.perform { [dailyBolusStats] in
            // Group by days
            let groupedByDay = Dictionary(grouping: dailyBolusStats) { stat in
                calendar.startOfDay(for: stat.date)
            }

            // Calculate totals for each day
            var totals: [(Date, Double)] = []
            for (day, stats) in groupedByDay {
                let total = stats.reduce(0.0) { _, stat in
                    stat.manualBolus + stat.smb + stat.external
                }
            }
            return totals
        }

        // Update cache on main thread
        await MainActor.run {
            self.bolusAveragesCache = dailyAverages
            self.bolusTotalsCache = dailyTotals
        }
    }

    /// Returns the average bolus values for the given date range from the cache
    /// - Parameter range: A tuple containing the start and end dates to get averages for
    /// - Returns: A tuple containing the average total, carb and correction bolus values for the date range
    func getCachedBolusAverages(for range: (start: Date, end: Date)) -> (manual: Double, smb: Double, external: Double) {
        return calculateBolusAveragesForDateRange(from: range.start, to: range.end)
    }

    /// Returns the total bolus values for the given date range from the cache
    /// - Parameter range: A tuple containing the start and end dates to get averages for
    /// - Returns: Totals for bolus (sum of manual, smb and external) for the date range
    func getCachedBolusTotals(for range: (start: Date, end: Date)) -> Double {
        calculateBolusTotalsForDateRange(from: range.start, to: range.end)
    }

    /// Calculates the average bolus values for a given date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: A tuple containing the average total, carb and correction bolus values for the date range
    func calculateBolusAveragesForDateRange(
        from startDate: Date,
        to endDate: Date
    ) -> (manual: Double, smb: Double, external: Double) {
        // Filter cached values to only include those within the date range
        let relevantStats = bolusAveragesCache.filter { date, _ in
            date >= startDate && date <= endDate
        }

        // Return zeros if no data exists for the range
        guard !relevantStats.isEmpty else { return (0, 0, 0) }

        // Calculate total bolus across all days
        let total = relevantStats.values.reduce((0.0, 0.0, 0.0)) { acc, avg in
            (acc.0 + avg.0, acc.1 + avg.1, acc.2 + avg.2)
        }

        // Calculate averages by dividing totals by number of days
        let count = Double(relevantStats.count)

        return (total.0 / count, total.1 / count, total.2 / count)
    }

    /// Calculates the total bolus values for a given date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: A total bolus (sum of manual, smb and external) for the date range
    func calculateBolusTotalsForDateRange(
        from startDate: Date,
        to endDate: Date
    ) -> Double {
        // Filter cached values to only include those within the date range
        let relevantStats = bolusAveragesCache.filter { date, _ in
            date >= startDate && date <= endDate
        }

        // Return zeros if no data exists for the range
        guard !relevantStats.isEmpty else { return 0 }

        // Calculate total bolus across all days
        return relevantStats.values.reduce(0.0) { _, totalPerCategory in
            totalPerCategory.0 + totalPerCategory.1 + totalPerCategory.2
        }
    }
}

/// Extension to convert Decimal to Double
private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
