import CoreData
import Foundation

/// Represents statistical data about bolus insulin delivery for a specific day
struct BolusStats: Identifiable {
    let id = UUID()
    /// The date representing this time period
    let date: Date
    /// Total amount of manual boluses (excluding SMB and external)
    let manualBolus: Double
    /// Total amount of Super Micro Boluses (SMB)
    let smb: Double
    /// Total amount of external boluses (e.g., from pump directly)
    let external: Double
}

extension Stat.StateModel {
    /// Updates the bolus statistics for the currently selected time period
    func updateBolusStats() {
        Task {
//            let stats = await fetchBolusStats(days: requestedDaysTDD, endDate: requestedEndDayTDD)
//            await MainActor.run {
//                self.bolusStats = stats
//            }
        }
    }

    /// Fetches and processes bolus statistics for a specific date range
    /// - Parameters:
    ///   - days: Number of days to fetch
    ///   - endDate: The end date of the range
    /// - Returns: Array of BolusStats containing daily bolus statistics
    func fetchBolusStats(days: Int, endDate: Date) async -> [BolusStats] {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: endDate)
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate)!

        // Fetch bolus records from Core Data
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: bolusTaskContext,
            predicate: NSPredicate(
                format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp < %@",
                startDate as NSDate,
                calendar.date(byAdding: .day, value: 1, to: endDate)! as NSDate
            ),
            key: "pumpEvent.timestamp",
            ascending: false,
            batchSize: 100
        )

        return await bolusTaskContext.perform {
            guard let fetchedResults = results as? [BolusStored] else { return [] }

            // Group entries by day
            let groupedEntries = Dictionary(grouping: fetchedResults) { entry in
                calendar.startOfDay(for: entry.pumpEvent?.timestamp ?? Date())
            }

            // Create array of all dates in the range
            var dates: [Date] = []
            var currentDate = startDate
            while currentDate <= endDate {
                dates.append(calendar.startOfDay(for: currentDate))
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }

            // Calculate statistics for each day
            return dates.map { date in
                let dayEntries = groupedEntries[date, default: []]

                // Calculate total manual boluses (excluding SMB and external)
                let manualBolus = dayEntries
                    .filter { !($0.isExternal || $0.isSMB) }
                    .reduce(0.0) { $0 + (($1.amount as? Decimal) ?? 0).doubleValue }

                // Calculate total SMB
                let smb = dayEntries
                    .filter { $0.isSMB }
                    .reduce(0.0) { $0 + (($1.amount as? Decimal) ?? 0).doubleValue }

                // Calculate total external boluses
                let external = dayEntries
                    .filter { $0.isExternal }
                    .reduce(0.0) { $0 + (($1.amount as? Decimal) ?? 0).doubleValue }

                return BolusStats(
                    date: date,
                    manualBolus: manualBolus,
                    smb: smb,
                    external: external
                )
            }.sorted { $0.date < $1.date }
        }
    }
}

/// Extension to convert Decimal to Double
private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
