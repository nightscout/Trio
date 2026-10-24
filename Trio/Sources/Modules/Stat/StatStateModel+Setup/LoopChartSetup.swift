import CoreData
import Foundation

struct LoopingStats: Identifiable {
    var id: Date { date }

    let date: Date
    let successful: Int
    let failed: Int
    let medianDuration: Double
    let medianInterval: Double
}

extension Stat.StateModel {
    func setupLoopStats() {
        Task {
            do {
                let (hourly, daily, earliestLoopDate) = try await fetchLoopStats()

                await MainActor.run {
                    self.hourlyLoopStats = hourly
                    self.dailyLoopStats = daily
                    self.earliestLoopDate = earliestLoopDate
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch loop stats: \(error)")
            }
        }
    }

    private static func makeLoopStats(date: Date, entries: [(date: Date, entry: LoopStatRecord)]) -> LoopingStats {
        let sums = entries.reduce((successful: 0, failed: 0)) { acc, item in
            guard item.entry.loopStatus?.contains("Success") == true else { return (acc.successful, acc.failed + 1) }
            return (acc.successful + 1, acc.failed)
        }
        let sortedDurations = entries
            .map(\.entry.duration)
            .sorted()
        // Zero or negative intervals are excluded so they cannot drag the median.
        let sortedIntervals = entries
            .filter { $0.entry.interval > 0 }
            .map(\.entry.interval)
            .sorted()

        return LoopingStats(
            date: date,
            successful: sums.successful,
            failed: sums.failed,
            medianDuration: StatChartUtils.percentile(0.5, of: sortedDurations),
            medianInterval: StatChartUtils.percentile(0.5, of: sortedIntervals)
        )
    }

    private func fetchLoopStats() async throws -> (hourly: [LoopingStats], daily: [LoopingStats], earliestLoopDate: Date?) {
        let loopTaskContext = CoreDataStack.shared.newTaskContext()
        loopTaskContext.name = "StatStateModel.fetchLoopStats"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: LoopStatRecord.self,
            onContext: loopTaskContext,
            predicate: NSPredicate(format: "start >= %@", Date.ninetyDaysAgo as NSDate),
            key: "start",
            ascending: true
        )

        return await loopTaskContext.perform {
            guard let fetchedResults = results as? [LoopStatRecord] else { return ([], [], nil) }

            let validEntries = fetchedResults.compactMap { entry -> (date: Date, entry: LoopStatRecord)? in
                guard let date = entry.start else { return nil }
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
                Self.makeLoopStats(date: $0.key, entries: $0.value)
            }

            let dailyStats = dailyGrouped.sorted { $0.key < $1.key }.map {
                Self.makeLoopStats(date: $0.key, entries: $0.value)
            }

            let earliestLoopDate = validEntries.first?.date

            return (hourlyStats, dailyStats, earliestLoopDate)
        }
    }

    func calculateLoopStats(for range: (start: Date, end: Date))
        -> (successful: Double, failed: Double, successRate: Double, coverage: Double)
    {
        let isDay = selectedIntervalForLoopStats == .day
        let stats = isDay ? hourlyLoopStats : dailyLoopStats
        let relevantStats = stats.filter { StatChartUtils.isStatInRange($0.date, in: range) }

        guard !relevantStats.isEmpty else { return (0, 0, 0.0, 0.0) }

        let sums = relevantStats.reduce((successful: 0, failed: 0)) { acc, entry in
            (acc.successful + entry.successful, acc.failed + entry.failed)
        }

        // Day view sums hourly buckets into a daily total and longer spans average across days.
        let divisor = isDay ? 1.0 : Double(relevantStats.count)
        let successRate = Double(sums.successful) / Double(sums.successful + sums.failed) * 100
        let coverage = Self.loopCoverage(successful: sums.successful, for: range, startDate: earliestLoopDate)

        return (Double(sums.successful) / divisor, Double(sums.failed) / divisor, successRate, coverage)
    }

    private static func loopCoverage(
        successful: Int,
        for range: (start: Date, end: Date),
        startDate: Date?
    ) -> Double {
        let expectedLoopInterval: TimeInterval = 5 * 60
        let now = Date()
        // Clamp to the first loop and now so fresh installs and unfinished days are not penalized.
        let start = max(range.start, startDate ?? range.start)
        let end = min(range.end, now)

        guard end > start else { return 0 }

        let expectedLoops = end.timeIntervalSince(start) / expectedLoopInterval
        // Forced loops can exceed the 5 minute schedule.
        return min(Double(successful) / expectedLoops * 100, 100)
    }
}
