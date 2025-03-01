import CoreData
import Foundation

/// Represents statistical data about Total Daily Dose for a specific time period
struct TDDStats: Identifiable {
    let id = UUID()
    /// The date representing this time period
    let date: Date
    /// Total insulin in units
    let amount: Double
}

extension Stat.StateModel {
    /// Sets up TDD statistics by fetching and processing insulin data
    func setupTDDStats() {
        Task {
            do {
                let (hourly, daily) = try await fetchTDDStats()

                await MainActor.run {
                    self.hourlyTDDStats = hourly
                    self.dailyTDDStats = daily
                }

                // Initially calculate and cache daily averages
                await calculateAndCacheTDDAverages()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed fetching TDD stats: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches and processes Total Daily Dose (TDD) statistics from CoreData
    /// - Returns: A tuple containing hourly and daily TDD statistics arrays
    /// - Note: Processes both hourly statistics for the last 10 days and complete daily statistics
    private func fetchTDDStats() async throws -> (hourly: [TDDStats], daily: [TDDStats]) {
        // MARK: - Fetch Required Data

        // Fetch data for daily statistics (TDDStored for week, month, total views)
        let tddResults = try await fetchTDDStoredRecords()

        // Fetch data for hourly statistics (BolusStored and TempBasalStored for day view)
        let (bolusResults, tempBasalResults) = try await fetchHourlyInsulinRecords()

        // MARK: - Process Data on Background Context

        var hourlyStats: [TDDStats] = []
        var dailyStats: [TDDStats] = []

        await tddTaskContext.perform {
            let calendar = Calendar.current

            // Process daily statistics from TDDStored
            if let fetchedTDDs = tddResults as? [TDDStored] {
                dailyStats = self.processDailyTDDs(fetchedTDDs, calendar: calendar)
            }

            // Process hourly statistics from BolusStored and TempBasalStored
            if let fetchedBoluses = bolusResults as? [BolusStored],
               let fetchedTempBasals = tempBasalResults as? [TempBasalStored]
            {
                hourlyStats = self.processHourlyInsulinData(
                    boluses: fetchedBoluses,
                    tempBasals: fetchedTempBasals,
                    calendar: calendar
                )
            }
        }

        return (hourlyStats, dailyStats)
    }

    /// Fetches TDDStored records from CoreData for daily statistics
    /// - Returns: The results of the fetch request containing TDDStored records
    /// - Note: Fetches records from the last 3 months for week, month, and total views
    private func fetchTDDStoredRecords() async throws -> Any {
        // Create a predicate to fetch TDD records from the last 3 months
        let threeMonthsAgo = Date().addingTimeInterval(-3.months.timeInterval)
        let predicate = NSPredicate(format: "date >= %@", threeMonthsAgo as NSDate)

        // Fetch TDD records from CoreData
        return try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: tddTaskContext,
            predicate: predicate,
            key: "date",
            ascending: true,
            batchSize: 100
        )
    }

    /// Fetches BolusStored and TempBasalStored records from CoreData for hourly statistics
    /// - Returns: A tuple containing the results of both fetch requests
    /// - Note: Fetches records from the last 20 days for detailed hourly view
    private func fetchHourlyInsulinRecords() async throws -> (bolus: Any, tempBasal: Any) {
        // Calculate date range for hourly statistics (last 20 days)
        let now = Date()
        let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: now) ?? now

        // Create a predicate for the date range
        let datePredicate = NSPredicate(
            format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
            twentyDaysAgo as NSDate,
            now as NSDate
        )

        // Fetch bolus records for hourly stats
        let bolusResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: tddTaskContext,
            predicate: datePredicate,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        // Fetch temp basal records for hourly stats
        let tempBasalResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempBasalStored.self,
            onContext: tddTaskContext,
            predicate: datePredicate,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        return (bolusResults, tempBasalResults)
    }

    /// Processes bolus and temporary basal data to create hourly insulin statistics
    /// - Parameters:
    ///   - boluses: Array of BolusStored objects containing bolus insulin data
    ///   - tempBasals: Array of TempBasalStored objects containing temporary basal rate data
    ///   - calendar: Calendar instance used for date calculations and grouping
    /// - Returns: Array of TDDStats objects representing hourly insulin amounts
    /// - Note: This method calculates the actual duration of temporary basal rates by using the time
    ///         difference between consecutive events, rather than relying on the planned duration.
    ///         It also properly distributes insulin amounts across hour boundaries for accurate hourly statistics.
    private func processHourlyInsulinData(
        boluses: [BolusStored],
        tempBasals: [TempBasalStored],
        calendar: Calendar
    ) -> [TDDStats] {
        // Dictionary to store insulin amounts indexed by hour
        var insulinByHour: [Date: Double] = [:]

        // MARK: - Process Bolus Insulin

        // Iterate through all bolus records and add their amounts to the appropriate hourly totals
        for bolus in boluses {
            guard let timestamp = bolus.pumpEvent?.timestamp,
                  let amount = bolus.amount?.doubleValue
            else {
                continue // Skip entries with missing timestamp or amount
            }

            // Create a date representing the hour of this bolus (truncating minutes/seconds)
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
            guard let hourDate = calendar.date(from: components) else { continue }

            // Add this bolus amount to the running total for this hour
            insulinByHour[hourDate, default: 0] += amount
        }

        // MARK: - Process Temporary Basal Insulin

        // Sort temp basals chronologically for accurate duration calculation
        let sortedTempBasals = tempBasals.sorted {
            ($0.pumpEvent?.timestamp ?? Date.distantPast) < ($1.pumpEvent?.timestamp ?? Date.distantPast)
        }

        // Process each temporary basal event
        for (index, tempBasal) in sortedTempBasals.enumerated() {
            guard let timestamp = tempBasal.pumpEvent?.timestamp,
                  let rate = tempBasal.rate?.doubleValue
            else {
                continue // Skip entries with missing timestamp or rate
            }

            // MARK: Calculate Actual Duration

            // Determine the actual duration based on the time until the next temp basal event
            var actualDurationInMinutes: Double

            if index < sortedTempBasals.count - 1 {
                // For all but the last event, calculate duration as time until next event
                if let nextTimestamp = sortedTempBasals[index + 1].pumpEvent?.timestamp {
                    // Calculate time difference in minutes between this event and the next
                    actualDurationInMinutes = nextTimestamp.timeIntervalSince(timestamp) / 60.0
                } else {
                    // Fallback to planned duration if next timestamp is missing (unlikely)
                    actualDurationInMinutes = Double(tempBasal.duration)
                }
            } else {
                // For the last event, use the planned duration as there's no next event
                actualDurationInMinutes = Double(tempBasal.duration)
            }

            // Convert duration from minutes to hours for insulin calculation
            let durationInHours = actualDurationInMinutes / 60.0

            // MARK: Distribute Insulin Across Hours

            // Handle temp basals that span multiple hours by distributing insulin appropriately
            distributeInsulinAcrossHours(
                startTime: timestamp,
                durationInHours: durationInHours,
                rate: rate,
                insulinByHour: &insulinByHour,
                calendar: calendar
            )
        }

        // MARK: - Convert Results to TDDStats Array

        // Transform the dictionary into a sorted array of TDDStats objects
        return insulinByHour.keys.sorted().map { hourDate in
            TDDStats(
                date: hourDate,
                amount: insulinByHour[hourDate, default: 0]
            )
        }
    }

    /// Distributes insulin from a temporary basal rate across multiple hours
    /// - Parameters:
    ///   - startTime: The start time of the temporary basal rate
    ///   - durationInHours: The duration of the temporary basal rate in hours
    ///   - rate: The insulin rate in units per hour (U/h)
    ///   - insulinByHour: Dictionary to store insulin amounts by hour (modified in-place)
    ///   - calendar: Calendar instance used for date calculations
    /// - Note: This method handles the case where a temporary basal spans multiple hours by
    ///         calculating the exact amount of insulin delivered in each hour. It accounts for
    ///         partial hours at the beginning and end of the temporary basal period.
    private func distributeInsulinAcrossHours(
        startTime: Date,
        durationInHours: Double,
        rate: Double,
        insulinByHour: inout [Date: Double],
        calendar: Calendar
    ) {
        // Extract time components to calculate partial hours
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: startTime)

        // Create a date representing just the hour of the start time (truncating minutes/seconds)
        guard let startHourDate = calendar
            .date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: startTime))
        else {
            return // Exit if we can't create a valid hour date
        }

        // MARK: - Handle First Hour (Partial)

        // Calculate how many minutes remain in the first hour after the start time
        let minutesInFirstHour = 60.0 - Double(startComponents.minute ?? 0) - (Double(startComponents.second ?? 0) / 60.0)

        // Calculate how many hours of the temp basal occur in the first hour (capped at remaining time)
        let hoursInFirstHour = min(durationInHours, minutesInFirstHour / 60.0)

        // Add insulin for the first partial hour
        if hoursInFirstHour > 0 {
            // Insulin = rate (U/h) * fraction of hour
            insulinByHour[startHourDate, default: 0] += rate * hoursInFirstHour
        }

        // MARK: - Handle Subsequent Hours

        // Calculate remaining duration after the first hour
        var remainingDuration = durationInHours - hoursInFirstHour

        // Start with the next hour
        var currentHourDate = calendar.date(byAdding: .hour, value: 1, to: startHourDate) ?? startHourDate

        // Distribute remaining insulin across subsequent hours
        while remainingDuration > 0 {
            // Calculate how much of this hour is covered (max 1 hour)
            let hoursToAdd = min(remainingDuration, 1.0)

            // Add insulin for this hour: rate (U/h) * fraction of hour
            insulinByHour[currentHourDate, default: 0] += rate * hoursToAdd

            // Reduce remaining duration and move to next hour
            remainingDuration -= hoursToAdd
            currentHourDate = calendar.date(byAdding: .hour, value: 1, to: currentHourDate) ?? currentHourDate
        }
    }

    /// Processes TDDStored records to create daily Total Daily Dose statistics
    /// - Parameters:
    ///   - tdds: Array of TDDStored objects containing daily insulin data
    ///   - calendar: Calendar instance used for date calculations and grouping
    /// - Returns: Array of TDDStats objects representing daily insulin amounts
    /// - Note: This method groups TDD records by day and uses only the last (most recent) entry
    ///         for each day, as this represents the complete TDD value for that day. This approach
    ///         is appropriate for week, month, and total views where we want the final daily totals.
    private func processDailyTDDs(_ tdds: [TDDStored], calendar: Calendar) -> [TDDStats] {
        // MARK: - Group TDDs by Calendar Day

        // Create a dictionary where keys are start-of-day dates and values are arrays of TDD entries for that day
        let dailyGrouped = Dictionary(grouping: tdds) { tdd in
            guard let timestamp = tdd.date else { return Date() }
            // Use start of day (midnight) as the key for grouping
            return calendar.startOfDay(for: timestamp)
        }

        // MARK: - Process Each Day's Entries

        // Create a TDDStats object for each day using the most recent TDD entry
        return dailyGrouped.keys.sorted().map { dayDate in
            // Get all TDD entries for this day
            let entries = dailyGrouped[dayDate, default: []]

            // MARK: - Sort and Select Most Recent Entry

            // Sort entries chronologically to find the most recent one for the day
            let sortedEntries = entries.sorted {
                ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast)
            }

            // MARK: - Create TDDStats from Most Recent Entry

            // The last entry in the sorted array contains the complete TDD for the day
            if let lastEntry = sortedEntries.last, let total = lastEntry.total?.doubleValue {
                // Create TDDStats with the day's date and the total insulin amount
                return TDDStats(
                    date: dayDate,
                    amount: total
                )
            } else {
                // Fallback if no valid entry exists for this day
                return TDDStats(
                    date: dayDate,
                    amount: 0.0
                )
            }
        }
    }

    /// Calculates and caches the daily averages of Total Daily Dose (TDD) insulin values
    /// - Note: This function runs asynchronously and updates the tddAveragesCache on the main actor
    private func calculateAndCacheTDDAverages() async {
        // Get calendar for date calculations
        let calendar = Calendar.current

        // Calculate daily averages on background context
        let dailyAverages = await tddTaskContext.perform { [dailyTDDStats] in
            // Group TDD stats by calendar day
            let groupedByDay = Dictionary(grouping: dailyTDDStats) { stat in
                calendar.startOfDay(for: stat.date)
            }

            // Calculate average TDD for each day
            var averages: [Date: Double] = [:]
            for (day, stats) in groupedByDay {
                // Sum up all TDD values for the day
                let total = stats.reduce(0.0) { $0 + $1.amount }
                let count = Double(stats.count)
                // Store average in dictionary
                averages[day] = total / count
            }
            return averages
        }

        // Update cache on main actor
        await MainActor.run {
            self.tddAveragesCache = dailyAverages
        }
    }

    /// Gets the cached average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameter range: A tuple containing the start and end dates to get averages for
    /// - Returns: The average TDD in units for the specified date range
    func getCachedTDDAverages(for range: (start: Date, end: Date)) -> Double {
        // Calculate and return the TDD averages for the given date range using cached values
        calculateTDDAveragesForDateRange(from: range.start, to: range.end)
    }

    /// Calculates the average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: The average TDD in units for the specified date range. Returns 0.0 if no data exists.
    private func calculateTDDAveragesForDateRange(from startDate: Date, to endDate: Date) -> Double {
        // Filter cached TDD values to only include those within the date range
        let relevantStats = tddAveragesCache.filter { date, _ in
            date >= startDate && date <= endDate
        }

        // Return 0 if no data exists for the specified range
        guard !relevantStats.isEmpty else { return 0.0 }

        // Calculate total TDD by summing all values
        let total = relevantStats.values.reduce(0.0, +)
        // Convert count to Double for floating point division
        let count = Double(relevantStats.count)

        // Return average TDD
        return total / count
    }
}
