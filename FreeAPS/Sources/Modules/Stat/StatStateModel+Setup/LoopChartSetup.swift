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
            let recordIDs = await self.fetchLoopStatRecords(for: selectedDurationForLoopStats)

            // Used for the Loop stats chart (success/failure percentages)
            let stats = await calculateLoopStats(from: recordIDs)

            // Update property on main thread to avoid data races
            await MainActor.run {
                self.groupedLoopStats = stats
            }

            // Used for the Loop duration chart (execution times)
            await self.updateLoopStatRecords(from: recordIDs)
        }
    }

    /// Fetches loop stat record IDs from Core Data based on the selected time duration
    /// - Parameter duration: The time period to fetch records for (Today, Day, Week, Month, or Total)
    /// - Returns: Array of NSManagedObjectIDs for the matching loop stat records
    func fetchLoopStatRecords(for duration: Duration) async -> [NSManagedObjectID] {
        // Create compound predicate combining duration and non-nil constraints
        let predicate: NSCompoundPredicate
        let durationPredicate: NSPredicate
        let nonNilDurationPredicate = NSPredicate(format: "duration != nil AND duration != 0")

        // Set up date-based predicate based on selected duration
        switch duration {
        case .Day,
             .Today:
            durationPredicate = NSPredicate(
                format: "end >= %@",
                Calendar.current.date(
                    byAdding: .day,
                    value: -2,
                    to: Calendar.current.startOfDay(for: Date())
                )! as CVarArg
            )
        case .Week:
            durationPredicate = NSPredicate(
                format: "end >= %@",
                Calendar.current.date(
                    byAdding: .day,
                    value: -7,
                    to: Calendar.current.startOfDay(for: Date())
                )! as CVarArg
            )
        case .Month:
            durationPredicate = NSPredicate(
                format: "end >= %@",
                Calendar.current.date(
                    byAdding: .month,
                    value: -1,
                    to: Calendar.current.startOfDay(for: Date())
                )! as CVarArg
            )
        case .Total:
            durationPredicate = NSPredicate(
                format: "end >= %@",
                Calendar.current.date(
                    byAdding: .month,
                    value: -3,
                    to: Calendar.current.startOfDay(for: Date())
                )! as CVarArg
            )
        }
        predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [durationPredicate, nonNilDurationPredicate])

        // Fetch records using the constructed predicate
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: LoopStatRecord.self,
            onContext: loopTaskContext,
            predicate: predicate,
            key: "end",
            ascending: false,
            batchSize: 100
        )

        return await loopTaskContext.perform {
            guard let fetchedResults = results as? [LoopStatRecord] else { return [] }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Calculates statistics for loop executions grouped by time periods
    /// - Parameter ids: Array of NSManagedObjectIDs for loop stat records
    /// - Returns: Array of LoopStatsByPeriod containing success/failure statistics
    func calculateLoopStats(from ids: [NSManagedObjectID]) async -> [LoopStatsByPeriod] {
        await loopTaskContext.perform {
            let calendar = Calendar.current
            let now = Date()

            // Convert IDs to LoopStatRecord objects
            let records = ids.compactMap { id -> LoopStatRecord? in
                do {
                    return try self.loopTaskContext.existingObject(with: id) as? LoopStatRecord
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Error fetching loop stat: \(error)")
                    return nil
                }
            }

            // Determine start date based on selected duration
            let startDate: Date
            switch self.selectedDurationForLoopStats {
            case .Day,
                 .Today:
                startDate = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))!
            case .Week:
                startDate = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
            case .Month:
                startDate = calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: now))!
            case .Total:
                startDate = calendar.date(byAdding: .month, value: -3, to: calendar.startOfDay(for: now))!
            }

            // Create array of all dates in the range
            var dates: [Date] = []
            var currentDate = startDate
            while currentDate <= now {
                dates.append(calendar.startOfDay(for: currentDate))
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }

            // Group records by day
            let recordsByDay = Dictionary(grouping: records) { record in
                guard let date = record.start else { return Date() }
                return calendar.startOfDay(for: date)
            }

            // Create stats for each day, including days with no data
            return dates.map { date in
                let dayRecords = recordsByDay[date, default: []]
                let successful = dayRecords.filter { $0.loopStatus?.contains("Success") ?? false }.count
                let failed = dayRecords.count - successful

                // Calculate glucose count for the period
                let glucoseFetchRequest = GlucoseStored.fetchRequest()
                let periodStart = date
                let periodEnd = calendar.date(byAdding: .day, value: 1, to: date)!

                glucoseFetchRequest.predicate = NSPredicate(
                    format: "date >= %@ AND date < %@",
                    periodStart as NSDate,
                    periodEnd as NSDate
                )

                var glucoseCount = 0
                do {
                    glucoseCount = try self.loopTaskContext.count(for: glucoseFetchRequest)
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Error counting glucose readings: \(error)")
                }

                return LoopStatsByPeriod(
                    period: date,
                    successful: successful,
                    failed: failed,
                    medianDuration: BareStatisticsView
                        .medianCalculationDouble(array: dayRecords.compactMap { $0.duration as Double? }),
                    glucoseCount: glucoseCount
                )
            }.sorted { $0.period < $1.period }
        }
    }

    /// Updates the loopStatRecords array on the main thread with records from the provided IDs
    /// - Parameter ids: Array of NSManagedObjectIDs for loop stat records
    @MainActor func updateLoopStatRecords(from ids: [NSManagedObjectID]) {
        loopStatRecords = ids.compactMap { id -> LoopStatRecord? in
            do {
                return try viewContext.existingObject(with: id) as? LoopStatRecord
            } catch {
                debugPrint("Error fetching loop stat: \(error)")
                return nil
            }
        }
    }
}
