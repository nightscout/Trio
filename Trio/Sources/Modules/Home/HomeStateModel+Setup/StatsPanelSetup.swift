import CoreData
import Foundation

/// Everything the home screen statistics panel renders, computed over the range
/// the user picked in Features > User Interface > Home Statistics Panel.
struct HomeStatsPanelStats: Sendable {
    var veryLowPct: Double = 0
    var lowPct: Double = 0
    var inRangePct: Double = 0
    var highPct: Double = 0
    var veryHighPct: Double = 0
    /// Mean glucose in mg/dL, nil without readings.
    var meanGlucose: Double?
    var glucoseCount: Int = 0
    var successfulLoops: Int = 0
    /// Insulin delivered in the range, in units.
    var totalInsulin: Double = 0
    /// Carbs entered in the range, in grams.
    var totalCarbs: Double = 0

    var hasGlucoseData: Bool { glucoseCount > 0 }

    /// Successful loops per glucose reading, clamped to 0...1. Nil without readings.
    ///
    /// A reading arrives every 5 minutes and Trio loops on it, so this is the share
    /// of readings that produced a loop — the same pair the Statistics screen charts
    /// as "Successful Loops" against "Glucose Count".
    var loopingPerformanceFraction: Double? {
        guard glucoseCount > 0 else { return nil }
        return min(max(Double(successfulLoops) / Double(glucoseCount), 0), 1)
    }
}

extension Home.StateModel {
    /// Recomputes the stats panel over the configured range.
    ///
    /// Cheap enough to run on every glucose update for `today`/`day`; the longer
    /// ranges read months of history, so all of it happens on a task context and
    /// only the finished value lands on the main actor.
    func refreshStatsPanelStats() {
        let range = settingsManager?.settings.homeStatsPanelRange ?? .today
        let timeInRangeType = settingsManager?.settings.timeInRangeType ?? .timeInTightRange
        let face = settingsManager?.settings.homeStatsPanelFace ?? .timeInRange

        // Nothing to show, so nothing to fetch.
        guard face != .none else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let stats = try await Self.computeStatsPanelStats(
                    range: range,
                    timeInRangeType: timeInRangeType,
                    needsInsulinAndCarbs: face == .totalDailyDose,
                    needsLoopCounts: face == .loopingPerformance
                )
                await MainActor.run {
                    self.statsPanelStats = stats
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to compute home stats panel stats: \(error)")
            }
        }
    }

    private static func computeStatsPanelStats(
        range: HomeStatsPanelRange,
        timeInRangeType: TimeInRangeType,
        needsInsulinAndCarbs: Bool,
        needsLoopCounts: Bool
    ) async throws -> HomeStatsPanelStats {
        let now = Date()
        let startDate = range.startDate(relativeTo: now)

        var stats = HomeStatsPanelStats()

        let readings = try await fetchGlucoseReadings(from: startDate, to: now)
        stats.glucoseCount = readings.count
        if !readings.isEmpty {
            stats.meanGlucose = readings.reduce(0.0) { $0 + Double($1.value) } / Double(readings.count)
            // fixed consensus TIR bound (StatStateModel.highLimit), not the user's
            // chart threshold, so the banner always matches the Stats screen
            let distribution = GlucoseDailyDistributionStats.compute(
                date: startDate,
                readings: readings,
                highLimit: 180,
                timeInRangeType: timeInRangeType
            )
            stats.veryLowPct = distribution.veryLowPct
            stats.lowPct = distribution.lowPct
            stats.inRangePct = distribution.inRangePct
            stats.highPct = distribution.highPct
            stats.veryHighPct = distribution.veryHighPct
        }

        if needsLoopCounts {
            stats.successfulLoops = try await countSuccessfulLoops(from: startDate, to: now)
        }

        if needsInsulinAndCarbs {
            async let insulin = totalInsulinDelivered(from: startDate, to: now)
            async let carbs = totalCarbsEntered(from: startDate, to: now)
            stats.totalInsulin = try await insulin
            stats.totalCarbs = try await carbs
        }

        return stats
    }

    // MARK: - Fetches

    private static func fetchGlucoseReadings(from startDate: Date, to endDate: Date) async throws -> [GlucoseReading] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "HomeStateModel.statsPanelGlucose"

        // dictionary rows keep three months of readings light
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate),
            key: "date",
            ascending: true,
            batchSize: 500,
            propertiesToFetch: ["glucose", "date"]
        )

        guard let rows = results as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let value = row["glucose"] as? Int, let date = row["date"] as? Date else { return nil }
            return GlucoseReading(value: value, date: date)
        }
    }

    private static func countSuccessfulLoops(from startDate: Date, to endDate: Date) async throws -> Int {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "HomeStateModel.statsPanelLoops"

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LoopStatRecord")
        request.predicate = NSPredicate(
            format: "start >= %@ AND start <= %@ AND loopStatus == %@",
            startDate as NSDate,
            endDate as NSDate,
            "Success"
        )

        return try await context.perform {
            try context.count(for: request)
        }
    }

    private static func totalCarbsEntered(from startDate: Date, to endDate: Date) async throws -> Double {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "HomeStateModel.statsPanelCarbs"

        // FPU rows are the same carbs spread over time; counting them would double-count
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate(
                format: "date >= %@ AND date <= %@ AND isFPU == %@",
                startDate as NSDate,
                endDate as NSDate,
                false as NSNumber
            ),
            key: "date",
            ascending: true,
            batchSize: 200,
            propertiesToFetch: ["carbs"]
        )

        guard let rows = results as? [[String: Any]] else { return 0 }
        return rows.reduce(0.0) { $0 + (($1["carbs"] as? Double) ?? 0) }
    }

    /// Bolus plus basal delivered inside the range.
    ///
    /// Finalized temp basal rows carry the pump-reported total, so those are used as
    /// stored (prorated when the row straddles a range edge). Only rows the pump has
    /// not finalized yet — in practice the temp basal still running — fall back to
    /// rate x time, resolved against whichever event superseded them.
    private static func totalInsulinDelivered(from startDate: Date, to endDate: Date) async throws -> Double {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "HomeStateModel.statsPanelInsulin"

        let bolusResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: context,
            predicate: NSPredicate(
                format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
                startDate as NSDate,
                endDate as NSDate
            ),
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 200
        )

        // reach back a day so a span that began before the range still contributes
        let basalResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempBasalStored.self,
            onContext: context,
            predicate: NSPredicate(
                format: "startDate >= %@ AND startDate <= %@",
                startDate.addingTimeInterval(-24 * 3600) as NSDate,
                endDate as NSDate
            ),
            key: "startDate",
            ascending: true,
            batchSize: 200
        )

        return await context.perform {
            var total = 0.0

            if let boluses = bolusResults as? [BolusStored] {
                total += boluses.reduce(0.0) { $0 + ($1.amount?.doubleValue ?? 0) }
            }

            guard let basals = basalResults as? [TempBasalStored] else { return total }

            for (index, basal) in basals.enumerated() {
                guard let start = basal.startDate else { continue }

                // A scheduled basal is stored open-ended; every row is superseded by
                // whatever came next, so clamp to that and to now either way.
                let nextStart = index < basals.count - 1 ? basals[index + 1].startDate : nil
                var end = basal.isScheduledBasal ? (nextStart ?? endDate) : (basal.endDate ?? start)
                if let nextStart { end = min(end, nextStart) }
                end = min(end, endDate)
                guard end > start else { continue }

                let overlapStart = max(start, startDate)
                let overlapEnd = min(end, endDate)
                guard overlapEnd > overlapStart else { continue }

                let overlapHours = overlapEnd.timeIntervalSince(overlapStart) / 3600
                if let delivered = basal.deliveredUnits?.doubleValue {
                    let spanHours = end.timeIntervalSince(start) / 3600
                    total += spanHours > 0 ? delivered * (overlapHours / spanHours) : delivered
                } else {
                    total += (basal.rate?.doubleValue ?? 0) * overlapHours
                }
            }

            return total
        }
    }
}
