import CoreData
import Foundation

extension Stat.StateModel {
    func setupTDDs() {
        Task {
            let tddStats = await fetchAndMapDeterminations()
            await MainActor.run {
                self.tddStats = tddStats
            }
        }
    }

    func fetchAndMapDeterminations() async -> [TDD] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: determinationFetchContext,
            predicate: NSPredicate.determinationsForStats,
            key: "deliverAt",
            ascending: true,
            propertiesToFetch: ["objectID", "timestamp", "deliverAt", "totalDailyDose"]
        )

        return await determinationFetchContext.perform {
            guard let fetchedResults = results as? [[String: Any]] else { return [] }

            // Group determinations by day
            let calendar = Calendar.current
            let groupedByDay = Dictionary(grouping: fetchedResults) { result -> Date in
                guard let deliverAt = result["deliverAt"] as? Date else { return Date() }
                return calendar.startOfDay(for: deliverAt)
            }

            // Calculate total daily doses for each day
            return groupedByDay.map { date, determinations -> TDD in
                let totalDose = determinations.reduce(Decimal.zero) { sum, determination in
                    sum + (determination["totalDailyDose"] as? Decimal ?? 0)
                }

                // Calculate average dose for the day
                let count = Decimal(determinations.count)
                let averageDose = count > 0 ? totalDose / count : 0

                return TDD(
                    totalDailyDose: averageDose,
                    timestamp: date
                )
            }
        }
    }

    var averageTDD: Decimal {
        let calendar = Calendar.current
        let now = Date()

        // Filter TDDs based on selected time frame
        let filteredTDDs: [TDD] = tddStats.filter { tdd in
            guard let timestamp = tdd.timestamp else { return false }

            switch selectedDurationForInsulinStats {
            case .Day:
                // Last 3 days
                let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
                return timestamp >= threeDaysAgo
            case .Week:
                // Last week
                let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
                return timestamp >= weekAgo
            case .Month:
                // Last month
                let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
                return timestamp >= monthAgo
            case .Total:
                // Last 3 months
                let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
                return timestamp >= threeMonthsAgo
            }
        }

        let sum = filteredTDDs.reduce(Decimal.zero) { $0 + ($1.totalDailyDose ?? 0) }
        return filteredTDDs.isEmpty ? 0 : sum / Decimal(filteredTDDs.count)
    }

    func calculateAverageTDD(from startDate: Date, to endDate: Date) async -> Decimal {
        let filteredTDDs = tddStats.filter { tdd in
            guard let timestamp = tdd.timestamp else { return false }
            return timestamp >= startDate && timestamp <= endDate
        }

        let sum = filteredTDDs.reduce(Decimal.zero) { $0 + ($1.totalDailyDose ?? 0) }
        return filteredTDDs.isEmpty ? 0 : sum / Decimal(filteredTDDs.count)
    }

    func calculateMedianTDD(from startDate: Date, to endDate: Date) async -> Decimal {
        let filteredTDDs = tddStats.filter { tdd in
            guard let timestamp = tdd.timestamp else { return false }
            return timestamp >= startDate && timestamp <= endDate
        }

        let sortedDoses = filteredTDDs.compactMap(\.totalDailyDose).sorted()
        guard !sortedDoses.isEmpty else { return 0 }

        let middle = sortedDoses.count / 2
        if sortedDoses.count % 2 == 0 {
            return (sortedDoses[middle - 1] + sortedDoses[middle]) / 2
        } else {
            return sortedDoses[middle]
        }
    }
}
