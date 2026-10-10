import CoreData
import Foundation

/// Represents statistical data about bolus insulin for a specific time period
struct BolusStats: Identifiable {
    var id: Date { date }
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
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to setup bolus stats: \(error)")
            }
        }
    }

    private static func makeStats(date: Date, entries: [(date: Date, entry: BolusStored)]) -> BolusStats {
        let sums = entries.reduce((manual: 0.0, smb: 0.0, external: 0.0)) { acc, item in
            let amount = item.entry.amount?.doubleValue ?? 0

            if item.entry.isSMB { return (acc.manual, acc.smb + amount, acc.external) }
            if item.entry.isExternal { return (acc.manual, acc.smb, acc.external + amount) }

            return (acc.manual + amount, acc.smb, acc.external)
        }
        return BolusStats(date: date, manualBolus: sums.manual, smb: sums.smb, external: sums.external)
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
        let bolusTaskContext = CoreDataStack.shared.newTaskContext()
        bolusTaskContext.name = "StatStateModel.fetchBolusStats"

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
            let twentyDaysAgo = calendar.date(byAdding: .day, value: -StatChartUtils.hourlyWindowDays, to: now)!

            let validEntries = fetchedResults.compactMap { entry -> (date: Date, entry: BolusStored)? in
                guard let date = entry.pumpEvent?.timestamp else { return nil }
                return (date, entry)
            }
            let lastTwentyDays = validEntries.filter { $0.date >= twentyDaysAgo && $0.date <= now }

            let hourlyGrouped = Dictionary(grouping: lastTwentyDays) {
                calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: $0.date))!
            }
            let dailyGrouped = Dictionary(grouping: validEntries) { calendar.startOfDay(for: $0.date) }

            // Process hourly stats
            hourlyStats = hourlyGrouped.sorted { $0.key < $1.key }.map {
                Self.makeStats(date: $0.key, entries: $0.value)
            }
            dailyStats = dailyGrouped.sorted { $0.key < $1.key }.map {
                Self.makeStats(date: $0.key, entries: $0.value)
            }
        }

        return (hourlyStats, dailyStats)
    }

    /// Calculates the average bolus values for a given date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: A tuple containing the average total, carb and correction bolus values for the date range
    func calculateBolusAverages(for range: (start: Date, end: Date)) -> (manual: Double, smb: Double, external: Double) {
        // Filter cached values to only include those within the date range
        let relevantStats = dailyBolusStats.filter { stat in
            StatChartUtils.isStatInRange(
                calendar.startOfDay(for: stat.date),
                in: range
            )
        }

        // Return zeros if no data exists for the range
        guard !relevantStats.isEmpty else { return (0, 0, 0) }

        // Calculate total bolus across all days
        let sums = relevantStats.reduce((0.0, 0.0, 0.0)) { acc, day in
            (acc.0 + day.manualBolus, acc.1 + day.smb, acc.2 + day.external)
        }

        // Calculate averages by dividing totals by number of days
        let count = Double(relevantStats.count)

        return (sums.0 / count, sums.1 / count, sums.2 / count)
    }

    func calculateBolusTotals(for range: (start: Date, end: Date)) -> (manual: Double, smb: Double, external: Double) {
        let relevantStats = hourlyBolusStats.filter { stat in
            StatChartUtils.isStatInRange(
                stat.date,
                in: range
            )
        }

        let sums = relevantStats.reduce((0.0, 0.0, 0.0)) { acc, hour in
            (acc.0 + hour.manualBolus, acc.1 + hour.smb, acc.2 + hour.external)
        }

        return sums
    }
}
