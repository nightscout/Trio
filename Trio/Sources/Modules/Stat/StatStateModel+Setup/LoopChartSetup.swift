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

extension Stat.StateModel {
    /// Initiates the process of fetching and processing loop statistics
    /// This function coordinates three main tasks:
    /// 1. Fetching loop stat record IDs for the selected duration
    /// 2. Calculating grouped statistics for the Loop stats chart
    /// 3. Updating loop stat records on the main thread (!) for the Loop duration chart
    func setupLoopStatRecords() {
        Task {
            do {
                let (recordIDs, failedRecordIDs) = try await self.fetchLoopStatRecords(for: selectedDurationForLoopStats)

                // Update loop records for duration chart
                await self.updateLoopStatRecords(allLoopIds: recordIDs)

                // Calculate statistics and update on main thread
                let stats = try await self.getLoopStats(
                    allLoopIds: recordIDs,
                    failedLoopIds: failedRecordIDs,
                    duration: selectedDurationForLoopStats
                )

                await MainActor.run {
                    self.loopStats = stats
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch loop stats: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches loop statistics records for the specified duration
    /// - Parameter duration: The time period to fetch records for
    /// - Returns: A tuple containing arrays of NSManagedObjectIDs for (all loops, failed loops)
    func fetchLoopStatRecords(for duration: Duration) async throws -> ([NSManagedObjectID], [NSManagedObjectID]) {
        // Calculate the date range based on selected duration
        let now = Date()
        let startDate: Date
        switch duration {
        case .Day:
            startDate = Calendar.current.startOfDay(for: now)
        case .Today:
            startDate = now.addingTimeInterval(-24.hours.timeInterval)
        case .Week:
            startDate = now.addingTimeInterval(-7.days.timeInterval)
        case .Month:
            startDate = now.addingTimeInterval(-30.days.timeInterval)
        case .Total:
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
    ///   - duration: The time period for statistics calculation
    /// - Returns: Array of tuples containing category, count and percentage for each statistic
    func getLoopStats(
        allLoopIds: [NSManagedObjectID],
        failedLoopIds: [NSManagedObjectID],
        duration: Duration
    ) async throws -> [(category: String, count: Int, percentage: Double)] {
        // Calculate the date range for glucose readings
        let now = Date()
        let startDate: Date
        switch duration {
        case .Day:
            startDate = Calendar.current.startOfDay(for: now)
        case .Today:
            startDate = now.addingTimeInterval(-24.hours.timeInterval)
        case .Week:
            startDate = now.addingTimeInterval(-7.days.timeInterval)
        case .Month:
            startDate = now.addingTimeInterval(-30.days.timeInterval)
        case .Total:
            startDate = now.addingTimeInterval(-90.days.timeInterval)
        }

        // Get glucose statistics
        let totalGlucose = try await calculateGlucoseStats(from: startDate, to: now)

        // Get NSManagedObject
        let allLoops = try await CoreDataStack.shared.getNSManagedObject(with: allLoopIds, context: loopTaskContext)
        let failedLoops = try await CoreDataStack.shared.getNSManagedObject(with: failedLoopIds, context: loopTaskContext)

        return await loopTaskContext.perform {
            let totalLoopsCount = allLoops.count
            let failedLoopsCount = failedLoops.count
            let successfulLoops = totalLoopsCount - failedLoopsCount
            let maxLoopsPerDay = 288.0 // Maximum possible loops per day (every 5 minutes)

            switch duration {
            case .Day:
                // For Day view: Calculate percentage based on maximum possible loops per day
                let loopPercentage = (Double(successfulLoops) / maxLoopsPerDay) * 100
                let glucosePercentage = (Double(totalGlucose) / maxLoopsPerDay) * 100

                return [
                    ("Loop Success Rate", successfulLoops, loopPercentage),
                    ("Glucose Count", totalGlucose, glucosePercentage)
                ]

            case .Month,
                 .Today,
                 .Total,
                 .Week:
                // For other views: Calculate average per day
                let numberOfDays = max(1, Calendar.current.dateComponents([.day], from: startDate, to: now).day ?? 1)

                let averageLoopsPerDay = Double(successfulLoops) / Double(numberOfDays)
                let averageGlucosePerDay = Double(totalGlucose) / Double(numberOfDays)

                let loopPercentage = (averageLoopsPerDay / maxLoopsPerDay) * 100
                let glucosePercentage = (averageGlucosePerDay / maxLoopsPerDay) * 100

                return [
                    ("Successful Loops", Int(round(averageLoopsPerDay)), loopPercentage),
                    ("Glucose Count", Int(round(averageGlucosePerDay)), glucosePercentage)
                ]
            }
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
