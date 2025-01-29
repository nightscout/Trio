import CoreData
import Foundation

extension Stat.StateModel {
    /// Initializes and fetches Total Daily Dose (TDD) statistics
    ///
    /// This function:
    /// 1. Fetches TDD determinations from CoreData
    /// 2. Maps the determinations to TDD records
    /// 3. Updates the tddStats array on the main thread
    func setupTDDs() {
        Task {
            let tddStats = await fetchAndMapDeterminations()
            await MainActor.run {
                self.tddStats = tddStats
            }
        }
    }

    /// Fetches and processes OpenAPS determinations to calculate Total Daily Doses
    /// - Returns: Array of TDD records sorted by date
    ///
    /// This function:
    /// 1. Fetches OpenAPS determinations from CoreData
    /// 2. Groups determinations by time period (day or hour based on selected duration)
    /// 3. Calculates average insulin doses for each time period
    ///
    /// The grouping logic:
    /// - For Day view: Groups by hour to show hourly distribution
    /// - For other views: Groups by day to show daily totals
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

            let calendar = Calendar.current

            // Group determinations by day or hour
            let groupedByTime = Dictionary(grouping: fetchedResults) { result -> Date in
                guard let deliverAt = result["deliverAt"] as? Date else { return Date() }

                if self.selectedDurationForInsulinStats == .Day {
                    // For Day view, group by hour
                    let components = calendar.dateComponents([.year, .month, .day, .hour], from: deliverAt)
                    return calendar.date(from: components) ?? Date()
                } else {
                    // For other views, group by day
                    return calendar.startOfDay(for: deliverAt)
                }
            }

            // Get all unique time points
            let timePoints = groupedByTime.keys.sorted()

            // Calculate totals for each time point
            return timePoints.map { timePoint in
                let determinations = groupedByTime[timePoint, default: []]

                let totalDose = determinations.reduce(Decimal.zero) { sum, determination in
                    sum + (determination["totalDailyDose"] as? Decimal ?? 0)
                }

                // Calculate average dose for the time period
                let count = Decimal(determinations.count)
                let averageDose = count > 0 ? totalDose / count : 0

                return TDD(
                    totalDailyDose: averageDose,
                    timestamp: timePoint
                )
            }
        }
    }

    /// Calculates the average Total Daily Dose for the currently selected time period
    ///
    /// Time periods and their ranges:
    /// - Day: Last 3 days
    /// - Week: Last 7 days
    /// - Month: Last 30 days
    /// - Total: Last 3 months
    ///
    /// Returns 0 if no TDD records are available for the selected period
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

    /// Calculates the average Total Daily Dose for a specified date range
    /// - Parameters:
    ///   - startDate: Start date of the range
    ///   - endDate: End date of the range
    /// - Returns: Average TDD value for the period
    ///
    /// The function:
    /// 1. Filters TDD records within the specified date range
    /// 2. Calculates the sum of all TDDs in the range
    /// 3. Returns the average (sum divided by number of records)
    /// 4. Returns 0 if no records are found
    func calculateAverageTDD(from startDate: Date, to endDate: Date) async -> Decimal {
        let filteredTDDs = tddStats.filter { tdd in
            guard let timestamp = tdd.timestamp else { return false }
            return timestamp >= startDate && timestamp <= endDate
        }

        let sum = filteredTDDs.reduce(Decimal.zero) { $0 + ($1.totalDailyDose ?? 0) }
        return filteredTDDs.isEmpty ? 0 : sum / Decimal(filteredTDDs.count)
    }

    /// Calculates the median Total Daily Dose for a specified date range
    /// - Parameters:
    ///   - startDate: Start date of the range
    ///   - endDate: End date of the range
    /// - Returns: Median TDD value for the period
    ///
    /// The calculation process:
    /// 1. Filters TDD records within the date range
    /// 2. Sorts all TDD values
    /// 3. For odd number of values: Returns the middle value
    /// 4. For even number of values: Returns average of two middle values
    /// 5. Returns 0 if no records are found
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
