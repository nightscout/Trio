import CoreData
import Foundation

/// Represents statistical data about loop execution success/failure for a specific time period
struct LoopStatsByPeriod: Identifiable {
    /// The date representing this time period
    let period: Date
    /// Number of successful loop executions in this period
    let successful: Int
    /// Number of failed loop executions in this period
    let failed: Int
    /// Median duration of loop executions in this period
    let medianDuration: Double
    /// Number of glucose measurements in this period
    let glucoseCount: Int
    /// Total number of loop executions in this period
    var total: Int { successful + failed }
    /// Percentage of successful loops (0-100)
    var successPercentage: Double { total > 0 ? Double(successful) / Double(total) * 100 : 0 }
    /// Percentage of failed loops (0-100)
    var failurePercentage: Double { total > 0 ? Double(failed) / Double(total) * 100 : 0 }
    /// Unique identifier for this period, using the period date
    var id: Date { period }
}

struct LoopStatsProcessedData: Identifiable {
    var id = UUID()
    let category: LoopStatsDataType
    let count: Int
    let percentage: Double
    let medianDuration: Double
    let medianInterval: Double
    let totalDays: Int
}

enum LoopStatsDataType: String {
    case successfulLoop
    case glucoseCount

    var displayName: String {
        switch self {
        case .successfulLoop: return String(localized: "Successful Loop")
        case .glucoseCount: return String(localized: "Glucose Count")
        }
    }
}

extension Stat.StateModel {
    /// Initiates the process of fetching and processing loop statistics
    /// This function coordinates three main tasks:
    /// 1. Fetching loop stat record IDs for the selected duration
    /// 2. Calculating grouped statistics for the Loop stats chart
    /// 3. Updating loop stat records on the main thread (!) for the Loop duration chart
    func setupLoopStatRecords() {
        Task {
            do {
                let (recordIDs, failedRecordIDs) = try await self.fetchLoopStatRecords(for: selectedIntervalForLoopStats)

                // Update loop records for duration chart
                await self.updateLoopStatRecords(allLoopIds: recordIDs)

                // Calculate statistics and update on main thread
                let stats = try await self.getLoopStats(
                    allLoopIds: recordIDs,
                    failedLoopIds: failedRecordIDs,
                    interval: selectedIntervalForLoopStats
                )

                await MainActor.run {
                    self.loopStats = stats
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch loop stats: \(error)")
            }
        }
    }

    /// Fetches loop statistics records for the specified duration
    /// - Parameter interval: The time period to fetch records for
    /// - Returns: A tuple containing arrays of NSManagedObjectIDs for (all loops, failed loops)
    func fetchLoopStatRecords(for interval: StatsTimeIntervalWithToday) async throws
        -> ([NSManagedObjectID], [NSManagedObjectID])
    {
        // Calculate the date range based on selected duration
        let now = Date()
        let startDate: Date
        switch interval {
        case .day:
            startDate = now.addingTimeInterval(-24.hours.timeInterval)
        case .today:
            startDate = Calendar.current.startOfDay(for: now)
        case .week:
            startDate = now.addingTimeInterval(-7.days.timeInterval)
        case .month:
            startDate = now.addingTimeInterval(-30.days.timeInterval)
        case .total:
            startDate = now.addingTimeInterval(-90.days.timeInterval)
        }

        // Perform both fetches asynchronously
        async let allLoopsResult = CoreDataStack.shared.fetchEntitiesAsync(
            ofType: LoopStatRecord.self,
            onContext: loopTaskContext,
            predicate: NSPredicate(format: "start > %@", startDate as NSDate),
            key: "start",
            ascending: false
        )

        async let failedLoopsResult = CoreDataStack.shared.fetchEntitiesAsync(
            ofType: LoopStatRecord.self,
            onContext: loopTaskContext,
            predicate: NSPredicate(
                format: "start > %@ AND loopStatus != %@",
                startDate as NSDate,
                "Success"
            ),
            key: "start",
            ascending: false
        )

        // Wait for both results and convert to object IDs
        let (allLoops, failedLoops) = try await (allLoopsResult, failedLoopsResult)

        return (
            (allLoops as? [LoopStatRecord] ?? []).map(\.objectID),
            (failedLoops as? [LoopStatRecord] ?? []).map(\.objectID)
        )
    }

    /// Updates the loopStatRecords array on the main thread with records from the provided IDs
    /// - Parameters:
    ///   - allLoopIds: Array of NSManagedObjectIDs for all loop records
    @MainActor func updateLoopStatRecords(allLoopIds: [NSManagedObjectID]) {
        loopStatRecords = allLoopIds.compactMap { id -> LoopStatRecord? in
            do {
                return try viewContext.existingObject(with: id) as? LoopStatRecord
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error fetching loop stat: \(error)")
                return nil
            }
        }
    }

    /// Calculates loop and glucose statistics based on the provided record IDs
    /// - Parameters:
    ///   - allLoopIds: Array of NSManagedObjectIDs for all loop records
    ///   - failedLoopIds: Array of NSManagedObjectIDs for failed loop records
    ///   - interval: The time period for statistics calculation
    /// - Returns: Array of tuples containing category, count and percentage for each statistic
    func getLoopStats(
        allLoopIds: [NSManagedObjectID],
        failedLoopIds: [NSManagedObjectID],
        interval: StatsTimeIntervalWithToday
    ) async throws
        -> [LoopStatsProcessedData]
    {
        // Calculate the date range for glucose readings
        let now = Date()
        let startDate: Date
        switch interval {
        case .day:
            startDate = now.addingTimeInterval(-24.hours.timeInterval)
        case .today:
            startDate = Calendar.current.startOfDay(for: now)
        case .week:
            startDate = now.addingTimeInterval(-7.days.timeInterval)
        case .month:
            startDate = now.addingTimeInterval(-30.days.timeInterval)
        case .total:
            startDate = now.addingTimeInterval(-90.days.timeInterval)
        }

        // Get glucose statistics
        let totalGlucose = try await calculateGlucoseStats(from: startDate, to: now)

        // Get NSManagedObject
        let allLoops = try await CoreDataStack.shared
            .getNSManagedObject(with: allLoopIds, context: loopTaskContext) as? [LoopStatRecord] ?? []
        let failedLoops = try await CoreDataStack.shared
            .getNSManagedObject(with: failedLoopIds, context: loopTaskContext) as? [LoopStatRecord] ?? []

        return await loopTaskContext.perform {
            let totalLoopsCount = allLoops.count
            let failedLoopsCount = failedLoops.count
            let successfulLoops = totalLoopsCount - failedLoopsCount
            let maxLoopsPerDay = 288.0 // Maximum possible loops per day (every 5 minutes)

            let numberOfDays = max(1, Calendar.current.dateComponents([.day], from: startDate, to: now).day ?? 1)
            let averageLoopsPerDay = Double(successfulLoops) / Double(numberOfDays)
            let averageGlucosePerDay = Double(totalGlucose) / Double(numberOfDays)

            // Calculate median duration (time from start to end of each loop)
            let sortedDurations: [TimeInterval] = allLoops.compactMap { loop in
                guard let start = loop.start, let end = loop.end else { return nil }
                return end.timeIntervalSince(start)
            }.sorted()
            let medianDuration = sortedDurations.isEmpty ? 0.0 : sortedDurations[sortedDurations.count / 2]

            // Calculate median interval (time between end of n-th loop and start of n+1th loop)
            let sortedIntervals: [TimeInterval] = zip(allLoops.dropLast(), allLoops.dropFirst()).compactMap { previous, next in
                guard let previousEnd = previous.end, let nextStart = next.start else { return nil }
                return previousEnd.timeIntervalSince(nextStart)
            }.sorted()
            let medianInterval = sortedIntervals.isEmpty ? 0.0 : sortedIntervals[sortedIntervals.count / 2]

            let loopPercentage = (averageLoopsPerDay / maxLoopsPerDay) * 100
            let glucosePercentage = (averageGlucosePerDay / maxLoopsPerDay) * 100

            return [
                LoopStatsProcessedData(
                    category: LoopStatsDataType.successfulLoop,
                    count: Int(round(averageLoopsPerDay)),
                    percentage: loopPercentage,
                    medianDuration: medianDuration,
                    medianInterval: medianInterval,
                    totalDays: numberOfDays
                ),
                LoopStatsProcessedData(
                    category: LoopStatsDataType.glucoseCount,
                    count: Int(round(averageGlucosePerDay)),
                    percentage: glucosePercentage,
                    medianDuration: medianDuration,
                    medianInterval: medianInterval,
                    totalDays: numberOfDays
                )
            ]
        }
    }

    /// Fetches and calculates glucose statistics for the given time period
    /// - Parameters:
    ///   - startDate: The start date of the period to analyze
    ///   - now: The current date (end of period)
    /// - Returns: Number of glucose readings in the period
    private func calculateGlucoseStats(
        from startDate: Date,
        to _: Date
    ) async throws -> Int {
        // Create predicate for glucose readings
        let glucosePredicate = NSPredicate(format: "date >= %@", startDate as NSDate)

        // Fetch glucose readings asynchronously
        let glucoseResult = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: loopTaskContext,
            predicate: glucosePredicate,
            key: "date",
            ascending: false
        )

        return await loopTaskContext.perform {
            guard let readings = glucoseResult as? [GlucoseStored] else {
                return 0
            }
            return readings.count
        }
    }
}
