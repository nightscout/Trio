import CoreData
import Foundation

struct BolusStats: Identifiable {
    var id: Date { date }
    let date: Date
    let manualBolus: Double
    let smb: Double
    let external: Double
}

extension Stat.StateModel {
    private typealias BolusEntry = (date: Date, amount: Double, isSMB: Bool, isExternal: Bool)
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

    private static func makeBolusStats(
        date: Date,
        entries: [BolusEntry]
    ) -> BolusStats {
        let sums = entries.reduce((manual: 0.0, smb: 0.0, external: 0.0)) { acc, bolusEntry in
            let amount = bolusEntry.amount

            if bolusEntry.isSMB { return (acc.manual, acc.smb + amount, acc.external) }
            if bolusEntry.isExternal { return (acc.manual, acc.smb, acc.external + amount) }

            return (acc.manual + amount, acc.smb, acc.external)
        }
        return BolusStats(date: date, manualBolus: sums.manual, smb: sums.smb, external: sums.external)
    }

    private func fetchBolusStats() async throws -> (hourly: [BolusStats], daily: [BolusStats]) {
        let bolusTaskContext = CoreDataStack.shared.newTaskContext()
        bolusTaskContext.name = "StatStateModel.fetchBolusStats"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: bolusTaskContext,
            predicate: NSPredicate.pumpHistoryForStats,
            key: "pumpEvent.timestamp",
            ascending: true,
            propertiesToFetch: ["amount", "isSMB", "isExternal", "pumpEvent.timestamp"]
        )
        guard let recordDictionaries = results as? [[String: Any]] else {
            throw CoreDataError.fetchError(function: #function, file: #file)
        }

        let validEntries: [BolusEntry] = recordDictionaries
            .compactMap { recordDictionary in
                guard let timestamp = recordDictionary["pumpEvent.timestamp"] as? Date else { return nil }
                let amount = (recordDictionary["amount"] as? NSNumber)?.doubleValue ?? 0
                let isSMB = (recordDictionary["isSMB"] as? NSNumber)?.boolValue ?? false
                let isExternal = (recordDictionary["isExternal"] as? NSNumber)?.boolValue ?? false
                return (date: timestamp, amount: amount, isSMB: isSMB, isExternal: isExternal)
            }

        let calendar = Calendar.current
        let now = Date()

        let twentyDaysAgo = calendar.date(byAdding: .day, value: -StatChartUtils.hourlyWindowDays, to: now)!
        let lastTwentyDays = validEntries.filter { $0.date >= twentyDaysAgo && $0.date <= now }

        let hourlyGrouped = Dictionary(grouping: lastTwentyDays) {
            calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: $0.date))!
        }
        let dailyGrouped = Dictionary(grouping: validEntries) { calendar.startOfDay(for: $0.date) }

        let hourlyStats = hourlyGrouped.sorted { $0.key < $1.key }.map {
            Self.makeBolusStats(date: $0.key, entries: $0.value)
        }
        let dailyStats = dailyGrouped.sorted { $0.key < $1.key }.map {
            Self.makeBolusStats(date: $0.key, entries: $0.value)
        }
        return (hourlyStats, dailyStats)
    }

    func calculateBolusAverages(for range: (start: Date, end: Date)) -> (manual: Double, smb: Double, external: Double) {
        let relevantStats = dailyBolusStats.filter { stat in
            StatChartUtils.isStatInRange(
                stat.date,
                in: range
            )
        }

        guard !relevantStats.isEmpty else { return (0, 0, 0) }

        let sums = relevantStats.reduce((0.0, 0.0, 0.0)) { acc, day in
            (acc.0 + day.manualBolus, acc.1 + day.smb, acc.2 + day.external)
        }

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
