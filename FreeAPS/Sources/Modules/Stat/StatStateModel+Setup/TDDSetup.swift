import CoreData
import Foundation

extension Stat.StateModel {
    func fetchAndMapDeterminations() async -> [TDD] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: determinationFetchContext,
            predicate: NSPredicate.determinationsForStats,
            key: "deliverAt",
            ascending: false,
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
            .sorted { ($0.timestamp ?? Date()) > ($1.timestamp ?? Date()) }
        }
    }
}
