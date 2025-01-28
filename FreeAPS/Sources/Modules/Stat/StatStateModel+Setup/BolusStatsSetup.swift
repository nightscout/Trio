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
    func setupBolusStats() {
        Task {
            let stats = await fetchBolusStats()
            await MainActor.run {
                self.bolusStats = stats
            }
        }
    }

    /// Fetches and processes bolus statistics for a specific date range
    /// - Returns: Array of BolusStats containing daily bolus statistics
    func fetchBolusStats() async -> [BolusStats] {
        let calendar = Calendar.current

        // Fetch bolus records from Core Data
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: bolusTaskContext,
            predicate: NSPredicate.pumpHistoryForStats,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        return await bolusTaskContext.perform {
            guard let fetchedResults = results as? [BolusStored] else { return [] }

            // Group boluses by day
            let groupedByDay = Dictionary(grouping: fetchedResults) { bolus -> Date in
                guard let timestamp = bolus.pumpEvent?.timestamp else { return Date() }
                return calendar.startOfDay(for: timestamp)
            }

            // Calculate daily totals
            return groupedByDay.map { date, boluses -> BolusStats in
                // Calculate total manual boluses (excluding SMB and external)
                let manualBolus = boluses
                    .filter { !($0.isExternal || $0.isSMB) }
                    .reduce(0.0) { $0 + (($1.amount as? Decimal) ?? 0).doubleValue }

                // Calculate total SMB
                let smb = boluses
                    .filter { $0.isSMB }
                    .reduce(0.0) { $0 + (($1.amount as? Decimal) ?? 0).doubleValue }

                // Calculate total external boluses
                let external = boluses
                    .filter { $0.isExternal }
                    .reduce(0.0) { $0 + (($1.amount as? Decimal) ?? 0).doubleValue }

                return BolusStats(
                    date: date,
                    manualBolus: manualBolus,
                    smb: smb,
                    external: external
                )
            }
        }
    }

    func calculateAverageBolus(from startDate: Date, to endDate: Date) -> (manual: Double, smb: Double, external: Double) {
        let visibleStats = bolusStats.filter { stat in
            stat.date >= startDate && stat.date <= endDate
        }

        guard !visibleStats.isEmpty else { return (0, 0, 0) }

        let count = Double(visibleStats.count)
        let manualSum = visibleStats.reduce(0.0) { $0 + $1.manualBolus }
        let smbSum = visibleStats.reduce(0.0) { $0 + $1.smb }
        let externalSum = visibleStats.reduce(0.0) { $0 + $1.external }

        return (
            manualSum / count,
            smbSum / count,
            externalSum / count
        )
    }
}

/// Extension to convert Decimal to Double
private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
