import CoreData
import Foundation

extension Decimal {
    func rounded(scale: Int, roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        var mutableSelf = self
        NSDecimalRound(&result, &mutableSelf, scale, roundingMode)
        return result
    }
}

extension Stat.StateModel {
    /// Represents different time ranges for Total Daily Dose calculations
    enum TDDTimeRange {
        /// Today
        case today
        /// Yesterday
        case yesterday
        /// Custom range with specified number of days and end date
        case customRange(days: Int, endDate: Date)

        /// Calculates the start and end dates for the time range
        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()

            switch self {
            case .today:
                let startOfToday = calendar.startOfDay(for: now)
                return (startOfToday, now)

            case .yesterday:
                let startOfToday = calendar.startOfDay(for: now)
                let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
                let endOfYesterday = calendar.date(byAdding: .second, value: -1, to: startOfToday)!
                return (startOfYesterday, endOfYesterday)

            case let .customRange(days, endDate):
                let endOfDay = calendar.date(
                    bySettingHour: 23,
                    minute: 59,
                    second: 59,
                    of: endDate
                )!
                let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endOfDay)!
                return (startDate, endOfDay)
            }
        }
    }

    /// Configuration for TDD display and calculations
    struct TDDConfiguration {
        /// Number of days to display in the TDD chart (default: 7)
        var requestedDays: Int = 7
        /// End date for the TDD chart, defaults to end of current day
        var endDate: Date = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: Date()
        ) ?? Date()
    }

    /// Result structure containing TDD calculations for a specific time range
    struct TDDResult: Sendable {
        /// Array of daily doses for the period
        let dailyDoses: [TDD]
        /// Average TDD for non-zero values
        let average: Decimal
        /// Time range for which the result was calculated
        let period: TDDTimeRange

        /// Total insulin dose for the period
        var totalDose: Decimal {
            dailyDoses.reduce(Decimal.zero) { $0 + ($1.totalDailyDose ?? 0) }
        }
    }

    /// Updates all TDD values concurrently: today, yesterday, and custom range
    /// This method fetches and processes TDD data for all time ranges in parallel
    /// and updates the UI state with the results.
    func updateTDDValues() async {
        // Fetch all required TDD ranges
        async let today = fetchTDDForRange(.today)
        async let yesterday = fetchTDDForRange(.yesterday)
        async let customRange = fetchTDDForRange(.customRange(
            days: tddConfig.requestedDays,
            endDate: tddConfig.endDate
        ))

        // Await all results
        let (todayResult, yesterdayResult, customRangeResult) = await (
            today, yesterday, customRange
        )

        // Update UI state
        await MainActor.run {
            currentTDD = todayResult.totalDose
            ytdTDDValue = yesterdayResult.totalDose
            averageTDD = customRangeResult.average
            dailyTotalDoses = customRangeResult.dailyDoses
        }
    }

    /// Fetches and processes TDD data for a specific time range
    /// - Parameter range: The time range for which to fetch TDD data
    /// - Returns: A TDDResult containing processed TDD data for the specified range
    private func fetchTDDForRange(_ range: TDDTimeRange) async -> TDDResult {
        let dateRange = range.dateRange

        let determinationIDs = await fetchDeterminations(
            from: dateRange.start,
            to: dateRange.end
        )

        let doses = await processDeterminations(determinationIDs, in: dateRange)
        let average = calculateAverage(from: doses)

        return TDDResult(
            dailyDoses: doses,
            average: average,
            period: range
        )
    }

    /// Fetches determination object IDs from Core Data for a given date range
    /// - Parameters:
    ///   - startDate: Start date of the range
    ///   - endDate: End date of the range
    /// - Returns: Array of NSManagedObjectIDs for matching determinations
    private func fetchDeterminations(from startDate: Date, to endDate: Date) async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: determinationFetchContext,
            predicate: NSPredicate.determinationPeriod(from: startDate, to: endDate),
            key: "deliverAt",
            ascending: false,
            propertiesToFetch: ["objectID", "timestamp", "deliverAt", "totalDailyDose"]
        )

        return await determinationFetchContext.perform {
            guard let fetchedResults = results as? [[String: Any]] else { return [] }
            return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
        }
    }

    /// Processes determination objects into TDD records
    /// - Parameters:
    ///   - determinationIDs: Array of determination object IDs to process
    ///   - dateRange: Date range for context (unused but kept for future use)
    /// - Returns: Array of processed TDD records, sorted by date descending
    private func processDeterminations(
        _ determinationIDs: [NSManagedObjectID],
        in _: (start: Date, end: Date)
    ) async -> [TDD] {
        await determinationFetchContext.perform {
            let calendar = Calendar.current

            // Convert IDs to OrefDetermination objects
            let determinations = determinationIDs.compactMap { id -> OrefDetermination? in
                do {
                    return try self.determinationFetchContext.existingObject(with: id) as? OrefDetermination
                } catch {
                    debugPrint("Error fetching determination: \(error)")
                    return nil
                }
            }

            // Group by day
            let groupedByDay = Dictionary(grouping: determinations) { determination in
                calendar.startOfDay(for: determination.timestamp ?? determination.deliverAt ?? Date())
            }

            // Get latest determination for each day
            return groupedByDay.compactMap { _, dayDeterminations in
                guard let latestDetermination = dayDeterminations.max(by: {
                    ($0.timestamp ?? $0.deliverAt ?? Date()) < ($1.timestamp ?? $1.deliverAt ?? Date())
                }),
                    let dose = latestDetermination.totalDailyDose as? Decimal
                else { return nil }

                return TDD(
                    totalDailyDose: dose,
                    timestamp: latestDetermination.deliverAt
                )
            }.sorted { ($0.timestamp ?? Date()) > ($1.timestamp ?? Date()) }
        }
    }

    /// Calculates the average TDD from an array of TDD records
    /// - Parameter tdds: Array of TDD records to average
    /// - Returns: Average TDD rounded to 1 decimal place, or 0 if no records
    private func calculateAverage(from tdds: [TDD]) -> Decimal {
        let totalSum = tdds.reduce(Decimal.zero) { $0 + ($1.totalDailyDose ?? 0) }
        let count = Decimal(tdds.count)

        guard count > 0 else { return 0 }
        return (totalSum / count).rounded(scale: 1, roundingMode: .plain)
    }
}
