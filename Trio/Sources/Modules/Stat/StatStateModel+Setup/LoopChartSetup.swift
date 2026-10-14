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
                let (hourly, daily) = try await fetchLoopStats()

                await MainActor.run {
                    self.hourlyLoopStats = hourly
                    self.dailyLoopStats = daily
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

    private func fetchLoopStats() async throws -> (hourly: [LoopingStats], daily: [LoopingStats]) {
        let loopTaskContext = CoreDataStack.shared.newTaskContext()
        loopTaskContext.name = "StatStateModel.fetchLoopStats"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: LoopStatRecord.self,
            onContext: loopTaskContext,
            predicate: NSPredicate(format: "start >= %@", Date.threeMonthsAgo as NSDate),
            key: "start",
            ascending: true
        )

        return await loopTaskContext.perform {
            guard let fetchedResults = results as? [LoopStatRecord] else { return ([], []) }

            let calendar = Calendar.current

            let now = Date()
            let twentyDaysAgo = calendar.date(byAdding: .day, value: -StatChartUtils.hourlyWindowDays, to: now)!

            let validEntries = fetchedResults.compactMap { entry -> (date: Date, entry: LoopStatRecord)? in
                guard let date = entry.start else { return nil }
                return (date, entry)
            }

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

            return (hourlyStats, dailyStats)
        }
    }

    func calculateLoopAverages(for range: (start: Date, end: Date)) -> (successful: Double, failed: Double, successRate: Double) {
        let relevantStats = dailyLoopStats.filter { stat in
            StatChartUtils.isStatInRange(
                calendar.startOfDay(for: stat.date),
                in: range
            )
        }

        guard !relevantStats.isEmpty else { return (0, 0, 0.0) }

        let sums = relevantStats.reduce((successful: 0, failed: 0)) { acc, day in
            (acc.successful + day.successful, acc.failed + day.failed)
        }

        let count = Double(relevantStats.count)
        let successRate = Double(sums.successful) / Double(sums.successful + sums.failed) * 100

        return (Double(sums.successful) / count, Double(sums.failed) / count, successRate)
    }

    func calculateLoopTotals(for range: (start: Date, end: Date)) -> (successful: Double, failed: Double, successRate: Double) {
        let relevantStats = hourlyLoopStats.filter { stat in
            StatChartUtils.isStatInRange(
                stat.date,
                in: range
            )
        }

        guard !relevantStats.isEmpty else { return (0, 0, 0.0) }

        let sums = relevantStats.reduce((successful: 0, failed: 0)) { acc, hour in
            (acc.successful + hour.successful, acc.failed + hour.failed)
        }
        let successRate = Double(sums.successful) / Double(sums.successful + sums.failed) * 100

        return (Double(sums.successful), Double(sums.failed), successRate)
    }
}
