import CoreData
import Foundation
import LoopKitUI
import Swinject

protocol TDDStorage {
    func calculateTDD(
        pumpManager: any PumpManagerUI,
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry]
    ) async throws
        -> TDDResult
    func storeTDD(_ tddResult: TDDResult) async
    func hasSufficientTDD() async throws -> Bool
}

/// Structure containing the results of TDD calculations
struct TDDResult {
    let total: Decimal
    let bolus: Decimal
    let tempBasal: Decimal
    let scheduledBasal: Decimal
    let weightedAverage: Decimal?
    let hoursOfData: Double
}

/// Implementation of the TDD Calculator
final class BaseTDDStorage: TDDStorage, Injectable {
    @Injected() private var storage: FileStorage!

    private let privateContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    /// Main function to calculate TDD from pump history and basal profile
    /// - Parameters:
    ///   - pumpManager: Representation of paired pump's PumpManagerUI
    ///   - pumpHistory: Array of pump history events
    ///   - basalProfile: Array of basal profile entries
    /// - Returns: TDDResult containing all calculated values
    func calculateTDD(
        pumpManager: any PumpManagerUI,
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry]
    ) async throws -> TDDResult {
        debug(.apsManager, "Starting TDD calculation with \(pumpHistory.count) pump events")

        // Log the first and last pump history events if available
        let earliestEvent: String
        let latestEvent: String

        // We fetch descending, so invert logic
        if let firstEvent = pumpHistory.last, let lastEvent = pumpHistory.first {
            earliestEvent = "Type: \(firstEvent.type), Timestamp: \(firstEvent.timestamp.ISO8601Format())"
            latestEvent = "Type: \(lastEvent.type), Timestamp: \(lastEvent.timestamp.ISO8601Format())"
        } else {
            earliestEvent = "No events available"
            latestEvent = "No events available"
            debug(.apsManager, "No pump history events available for logging.")
        }

        // Group events by type once to avoid multiple filters
        let groupedEvents = Dictionary(grouping: pumpHistory, by: { $0.type })
        let bolusEvents = groupedEvents[.bolus] ?? []
        let tempBasalEvents = groupedEvents[.tempBasal] ?? []
        let pumpSuspendEvents = groupedEvents[.pumpSuspend] ?? []
        let pumpResumeEvents = groupedEvents[.pumpResume] ?? []

        // Create pairs of suspend + resume events
        let suspendResumePairs = zip(pumpSuspendEvents, pumpResumeEvents).filter { suspend, resume in
            resume.timestamp > suspend.timestamp
        }

        // Calculate all components concurrently
        async let pumpDataHours = calculatePumpDataHours(pumpHistory)
        async let bolusInsulin = calculateBolusInsulin(bolusEvents)
        let gaps = findBasalGaps(in: tempBasalEvents)
        async let scheduledBasalInsulin = !gaps.isEmpty ? calculateScheduledBasalInsulin(
            gaps: gaps,
            profile: basalProfile,
            roundToSupportedBasalRate: pumpManager.roundToSupportedBasalRate
        ) : 0
        async let tempBasalInsulin = calculateTempBasalInsulin(
            tempBasalEvents, suspendResumePairs: suspendResumePairs,
            roundToSupportedBasalRate: pumpManager.roundToSupportedBasalRate
        )
        async let weightedAverage = calculateWeightedAverage()

        // Await all concurrent calculations
        let (hours, bolus, scheduled, temp, weighted) = try await (
            pumpDataHours,
            bolusInsulin,
            scheduledBasalInsulin,
            tempBasalInsulin,
            weightedAverage
        )

        // Total insulin calculation
        let total = bolus + temp + scheduled

        // Safeguard against division by zero
        let percentage: (Decimal, Decimal) -> String = { part, total in
            total > 0 ? String(format: "%.2f", NSDecimalNumber(decimal: (part / total * 100).rounded(toPlaces: 2)).doubleValue) :
                "0.00"
        }

        // Store log strings in variables to avoid Xcode auto formatter from breaking up the lines in log statement
        let totalString = String(format: "%.2f", NSDecimalNumber(decimal: total.rounded(toPlaces: 2)).doubleValue)
        let bolusString = String(format: "%.2f", NSDecimalNumber(decimal: bolus.rounded(toPlaces: 2)).doubleValue)
        let tempBasalString = String(format: "%.2f", NSDecimalNumber(decimal: temp.rounded(toPlaces: 2)).doubleValue)
        let scheduledBasalString = String(format: "%.2f", NSDecimalNumber(decimal: scheduled.rounded(toPlaces: 2)).doubleValue)
        let weightedAvgString = String(format: "%.2f", NSDecimalNumber(decimal: weighted?.rounded(toPlaces: 2) ?? 0).doubleValue)
        let hoursString = String(format: "%.5f", NSDecimalNumber(decimal: Decimal(hours).truncated(toPlaces: 5)).doubleValue)

        debug(.apsManager, """
        TDD Summary:
        +-------------------+-----------+-----------+
        | Type\t\t\t\t| Amount U\t| Percent %\t|
        +-------------------+-----------+-----------+
        | Total\t\t\t\t| \(totalString)\t\t| \t\t\t|
        | Bolus\t\t\t\t| \(bolusString)\t\t| \(percentage(bolus, total))\t\t|
        | Temp Basal\t\t| \(tempBasalString)\t\t| \(percentage(temp, total))\t\t|
        | Scheduled Basal\t| \(scheduledBasalString)\t\t| \(percentage(scheduled, total))\t\t|
        | Weighted Average\t| \(weightedAvgString)\t\t| \t\t\t|
        +-------------------+-----------+-----------+
        - Hours of Data: \(hoursString)
        - Earliest Event: \(earliestEvent)
        - Latest Event: \(latestEvent)
        """)

        // Return calculated TDDResult
        return TDDResult(
            total: total,
            bolus: bolus,
            tempBasal: temp,
            scheduledBasal: scheduled,
            weightedAverage: weighted,
            hoursOfData: hours
        )
    }

    /// Stores the Total Daily Dose (TDD) result in Core Data
    /// - Parameter tddResult: The TDD result to store, containing total insulin, bolus, temp basal, scheduled basal and weighted average
    func storeTDD(_ tddResult: TDDResult) async {
        await privateContext.perform {
            let tddStored = TDDStored(context: self.privateContext)
            tddStored.id = UUID()
            tddStored.date = Date()
            tddStored.total = NSDecimalNumber(decimal: tddResult.total)
            tddStored.bolus = NSDecimalNumber(decimal: tddResult.bolus)
            tddStored.tempBasal = NSDecimalNumber(decimal: tddResult.tempBasal)
            tddStored.scheduledBasal = NSDecimalNumber(decimal: tddResult.scheduledBasal)
            tddStored.weightedAverage = tddResult.weightedAverage.map { NSDecimalNumber(decimal: $0) }

            do {
                guard self.privateContext.hasChanges else { return }
                try self.privateContext.save()
            } catch {
                debug(.apsManager, "\(DebuggingIdentifiers.failed) Failed to save TDD: \(error)")
            }
        }
    }

    /// Calculates the number of hours of available pump history data
    /// - Parameter pumpHistory: Array of pump history events
    /// - Returns: Number of hours of available data
    private func calculatePumpDataHours(_ pumpHistory: [PumpHistoryEvent]) -> Double {
        guard let firstEvent = pumpHistory.last, // we are fetching in a descending order
              let lastEvent = pumpHistory.first
        else {
            return 0
        }

        let startDate = firstEvent.timestamp
        var endDate = lastEvent.timestamp

        // If last event in the list is tempBasal, check if it is running longer than current time
        // If yes, set current date, else ignore
        if lastEvent.type == .tempBasal, lastEvent.timestamp > Date().addingTimeInterval(-1) {
            endDate = Date()
        }

        return Double(endDate.timeIntervalSince(startDate)) / 3600.0
    }

    /// Calculates total bolus insulin from pump history
    /// - Parameter bolusEvents: Array of pump history events of type bolus
    /// - Returns: Total bolus insulin
    private func calculateBolusInsulin(_ bolusEvents: [PumpHistoryEvent]) -> Decimal {
        bolusEvents
            .reduce(Decimal(0)) { totalBolusInsulin, event in
//                let newTotalBolusInsulin =
                totalBolusInsulin + (event.amount as Decimal? ?? 0)
//                debug(
//                    .apsManager,
//                    "Bolus \(event.amount ?? 0) U dosed at \(event.timestamp.ISO8601Format()) added. New total bolus = \(newTotalBolusInsulin) U"
//                )
//                return newTotalBolusInsulin
            }
    }

    /// Calculates temporary basal insulin delivery for a given time period, accounting for interruptions and suspensions
    /// - Parameters:
    ///   - tempBasalEvents: Array of temporary basal events
    ///   - suspendResumePairs: Array of suspend and resume event pairs
    ///   - roundToSupportedBasalRate: Closure to round rates to pump-supported values
    /// - Returns: Total insulin delivered via temporary basal rates in units
    private func calculateTempBasalInsulin(
        _ tempBasalEvents: [PumpHistoryEvent],
        suspendResumePairs: [(suspend: PumpHistoryEvent, resume: PumpHistoryEvent)],
        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    ) -> Decimal {
        guard !tempBasalEvents.isEmpty else { return 0 }

        // Merge temp basal events and suspend-resume pairs into a single timeline
        var timeline = [(start: Date, end: Date, type: EventType, rate: Decimal?)]()

        // Add temp basal events to the timeline
        for event in tempBasalEvents {
            guard let duration = event.duration, let rate = event.amount else { continue }
            let end = event.timestamp.addingTimeInterval(TimeInterval(duration * 60))
            timeline.append((start: event.timestamp, end: end, type: .tempBasal, rate: rate))
        }

        // Add suspend-resume events to the timeline
        for suspendResume in suspendResumePairs {
            timeline.append((
                start: suspendResume.suspend.timestamp,
                end: suspendResume.resume.timestamp,
                type: .pumpSuspend,
                rate: nil
            ))
        }

        // Sort the timeline by start time
        timeline.sort { $0.start < $1.start }

        // Calculate insulin delivery while accounting for suspensions and premature interruptions
        var totalInsulin: Decimal = 0
        let currentDate = Date()
        var lastEndTime: Date?

        for (index, event) in timeline.enumerated() {
            if event.type == .tempBasal {
                let effectiveEnd = min(event.end, currentDate) // Adjust for ongoing temp basals
                var actualStart = event.start
                var actualEnd = effectiveEnd

                // Check for interruption by the next event
                if index < timeline.count - 1 {
                    let nextEvent = timeline[index + 1]
                    if nextEvent.start < actualEnd, nextEvent.type != .pumpSuspend {
                        actualEnd = nextEvent.start
                    }
                }

                // Adjust for overlapping suspensions
                if let lastSuspendEnd = lastEndTime, lastSuspendEnd > actualStart {
                    actualStart = lastSuspendEnd
                }

                // Calculate insulin if the duration is valid
                let durationMinutes = max(0, actualEnd.timeIntervalSince(actualStart) / 60)
                if durationMinutes > 0, let rate = event.rate {
                    let durationHours = (Decimal(durationMinutes) / 60).truncated(toPlaces: 5)
                    let insulin = Decimal(roundToSupportedBasalRate(Double(rate * durationHours)))
                    if insulin > 0 {
                        totalInsulin += insulin

//                        debug(
//                            .apsManager,
//                            "Temp basal: \(rate) U/hr for \(durationHours) hr (Start: \(actualStart.ISO8601Format()), End: \(actualEnd.ISO8601Format())) = \(insulin) U"
//                        )
                    }
                }
            } else if event.type == .pumpSuspend {
                // Update the last suspend end time to adjust future temp basal durations
                lastEndTime = event.end
            }
        }

        return totalInsulin
    }

    /// Calculates scheduled basal insulin delivery during gaps between temporary basals
    /// - Parameters:
    ///   - gaps: Array of time periods where scheduled basal was active
    ///   - profile: Basal profile entries defining rates throughout the day
    ///   - roundToSupportedBasalRate: Closure to round rates to pump-supported values
    /// - Returns: Total insulin delivered via scheduled basal in units
    private func calculateScheduledBasalInsulin(
        gaps: [(start: Date, end: Date)],
        profile: [BasalProfileEntry],
        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    ) -> Decimal {
        // Initialize cached formatter for time string conversion
        let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        // Pre-calculate profile switch times for efficient lookup
        let profileSwitches = profile.map(\.minutes)

        return gaps.reduce(into: Decimal(0)) { totalInsulin, gap in
            var currentTime = gap.start
            let now = Date()

            while currentTime < gap.end {
                // Find applicable basal rate for current time
                guard let rate = findBasalRate(
                    for: timeFormatter.string(from: currentTime),
                    in: profile
                ) else { break }

                // Determine when rate changes (either profile switch or gap end)
                let nextSwitchTime = getNextBasalRateSwitch(
                    after: currentTime,
                    switches: profileSwitches,
                    calendar: Calendar.current
                ) ?? gap.end

                // Ensure endTime does not exceed current time or gap end
                let endTime = min(min(nextSwitchTime, gap.end), now)

                // Only proceed if we have a valid time interval
                guard endTime > currentTime else { break }

                let durationHours = (Decimal(endTime.timeIntervalSince(currentTime)) / 3600).truncated(toPlaces: 5)
                let insulin = Decimal(roundToSupportedBasalRate(Double(rate * durationHours)))

                if insulin > 0 {
                    totalInsulin += insulin

//                    debug(
//                        .apsManager,
//                        "Scheduled Insulin added: \(insulin) U. Duration: \(durationHours) hrs (Start: \(currentTime.ISO8601Format()), End: \(endTime.ISO8601Format()))"
//                    )
                }

                currentTime = endTime
            }
        }
    }

    /// Finds gaps between tempBasal events where scheduled basal ran
    /// - Parameter tempBasalEvents: Array of pump history events of type tempBasal
    /// - Returns: Array of gaps, where each gap has a start and end time
    private func findBasalGaps(in tempBasalEvents: [PumpHistoryEvent]) -> [(start: Date, end: Date)] {
        guard !tempBasalEvents.isEmpty else {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            return [(start: startOfDay, end: startOfDay.addingTimeInterval(24 * 60 * 60 - 1))]
        }

        // Pre-sort events and create array with capacity
        let sortedEvents = tempBasalEvents.sorted { $0.timestamp < $1.timestamp }
        var gaps = [(start: Date, end: Date)]()
        gaps.reserveCapacity(sortedEvents.count + 1)

        // Use first event's date for calendar operations
        let startOfDay = Calendar.current.startOfDay(for: sortedEvents.first!.timestamp)
        let endOfDay = startOfDay.addingTimeInterval(24 * 60 * 60 - 1)

        // Process events in a single pass
        var lastEndTime = sortedEvents.first!.timestamp

        for i in 0 ..< sortedEvents.count {
            let event = sortedEvents[i]
            guard let duration = event.duration else { continue }

            // Calculate end time for current event
            var currentEndTime = event.timestamp.addingTimeInterval(TimeInterval(duration * 60))

            // Check for cancellation by next event
            if i < sortedEvents.count - 1 {
                let nextEvent = sortedEvents[i + 1]
                if nextEvent.timestamp < currentEndTime {
                    currentEndTime = nextEvent.timestamp
                }
            }

            // Record gap if exists
            if event.timestamp > lastEndTime {
                gaps.append((start: lastEndTime, end: event.timestamp))
            }

            lastEndTime = currentEndTime
        }

        // Add final gap if needed
        if lastEndTime < endOfDay {
            gaps.append((start: lastEndTime, end: endOfDay))
        }

        return gaps
    }

    //    /// Finds gaps between tempBasal events where scheduled basal ran, excluding suspend-resume periods
    //    /// - Parameters:
    //    ///   - tempBasalEvents: Array of pump history events of type tempBasal
    //    ///   - suspendResumePairs: Array of suspend and resume event pairs
    //    /// - Returns: Array of gaps, where each gap has a start and end time
    //    private func findBasalGaps(
    //        in tempBasalEvents: [PumpHistoryEvent],
    //        excluding suspendResumePairs: [(suspend: PumpHistoryEvent, resume: PumpHistoryEvent)]
    //    ) -> [(start: Date, end: Date)] {
    //        guard !tempBasalEvents.isEmpty else {
    //            let startOfDay = Calendar.current.startOfDay(for: Date())
    //            return [(start: startOfDay, end: startOfDay.addingTimeInterval(24 * 60 * 60 - 1))]
    //        }
    //
    //        // Merge temp basal and suspend-resume events into a unified timeline
    //        var timeline = [(start: Date, end: Date, type: EventType)]()
    //
    //        for event in tempBasalEvents {
    //            guard let duration = event.duration else { continue }
    //            let eventEnd = event.timestamp.addingTimeInterval(TimeInterval(duration * 60))
    //            timeline.append((start: event.timestamp, end: eventEnd, type: .tempBasal))
    //        }
    //
    //        for suspendResume in suspendResumePairs {
    //            timeline.append((start: suspendResume.suspend.timestamp, end: suspendResume.resume.timestamp, type: .pumpSuspend))
    //        }
    //
    //        // Sort the timeline by start time
    //        timeline.sort { $0.start < $1.start }
    //
    //        // Process the timeline to calculate gaps
    //        var gaps = [(start: Date, end: Date)]()
    //        var lastEndTime = Calendar.current.startOfDay(for: timeline.first!.start)
    //        let endOfDay = lastEndTime.addingTimeInterval(24 * 60 * 60 - 1)
    //
    //        for interval in timeline {
    //            if interval.type == .pumpSuspend {
    //                // Extend lastEndTime for suspend periods
    //                lastEndTime = max(lastEndTime, interval.end)
    //                continue
    //            }
    //
    //            if interval.start > lastEndTime {
    //                // Add a gap if there is a gap between lastEndTime and interval.start
    //                gaps.append((start: lastEndTime, end: interval.start))
    //            }
    //
    //            // Update lastEndTime to the maximum end time encountered
    //            lastEndTime = max(lastEndTime, interval.end)
    //        }
    //
    //        if lastEndTime < endOfDay {
    //            // Add a final gap if the lastEndTime is before the end of the day
    //            gaps.append((start: lastEndTime, end: endOfDay))
    //        }
    //
    //        return gaps
    //    }

    //    /// Calculates scheduled basal insulin delivery during gaps between temporary basals
    //    /// - Parameters:
    //    ///   - gaps: Array of time periods where scheduled basal was active
    //    ///   - profile: Basal profile entries defining rates throughout the day
    //    ///   - roundToSupportedBasalRate: Closure to round rates to pump-supported values
    //    /// - Returns: Total insulin delivered via scheduled basal in units
    //    private func calculateScheduledBasalInsulin(
    //        gaps: [(start: Date, end: Date)],
    //        profile: [BasalProfileEntry],
    //        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    //    ) -> Decimal {
    //        // Initialize cached formatter for time string conversion
    //        let timeFormatter: DateFormatter = {
    //            let formatter = DateFormatter()
    //            formatter.dateFormat = "HH:mm:ss"
    //            return formatter
    //        }()
    //
    //        // Pre-calculate profile switch times for efficient lookup
    //        let profileSwitches = profile.map(\.minutes)
    //
    //        return gaps.reduce(into: Decimal(0)) { totalInsulin, gap in
    //            var currentTime = gap.start
    //
    //            while currentTime < gap.end {
    //                // Find applicable basal rate for the current time
    //                guard let rate = findBasalRate(
    //                    for: timeFormatter.string(from: currentTime),
    //                    in: profile
    //                ) else { break }
    //
    //                // Determine when the rate changes (profile switch or gap end)
    //                let nextSwitchTime = getNextBasalRateSwitch(
    //                    after: currentTime,
    //                    switches: profileSwitches,
    //                    calendar: Calendar.current
    //                ) ?? gap.end
    //                let endTime = min(nextSwitchTime, gap.end)
    //                let durationHours = Decimal(endTime.timeIntervalSince(currentTime)) / 3600
    //
    //                let insulin = Decimal(roundToSupportedBasalRate(Double(rate * durationHours)))
    //                totalInsulin += insulin
    //
    //                debug(
    //                    .apsManager,
    //                    "Scheduled Insulin added: \(insulin) U. Duration: \(durationHours) hrs (\(currentTime)-\(endTime))"
    //                )
    //
    //                currentTime = endTime
    //            }
    //        }
    //    }

    /// Finds the next basal rate switch time after a given time
    /// - Parameters:
    ///   - time: Reference time to find next switch after
    ///   - switches: Pre-calculated array of minutes when profile rates change
    ///   - calendar: Calendar instance for date calculations
    /// - Returns: Date of next basal rate switch, or nil if none found
    private func getNextBasalRateSwitch(
        after time: Date,
        switches: [Int],
        calendar: Calendar
    ) -> Date? {
        let timeMinutes = calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time)

        // Find first switch time after current time
        guard let nextSwitch = switches.first(where: { $0 > timeMinutes }) else {
            return nil
        }

        // Convert switch time to absolute date
        return calendar.startOfDay(for: time).addingTimeInterval(TimeInterval(nextSwitch * 60))
    }

    /// Finds the basal rate for a specific time using binary search
    /// - Parameters:
    ///   - timeString: Time in format "HH:mm:ss"
    ///   - profile: Array of basal profile entries sorted by time
    /// - Returns: Basal rate in units per hour, or nil if not found
    private func findBasalRate(for timeString: String, in profile: [BasalProfileEntry]) -> Decimal? {
        // Parse time string in "HH:mm:ss" format into hours and minutes components
        let timeComponents = timeString.split(separator: ":")
        guard timeComponents.count == 3,
              let hours = Int(timeComponents[0]),
              let minutes = Int(timeComponents[1])
        else { return nil }

        // Convert time to total minutes since midnight for easier comparison
        let totalMinutes = hours * 60 + minutes

        // Special case: If profile has only one entry, it applies for full 24 hours
        // Return its rate immediately without searching
        if profile.count == 1 {
            return profile[0].rate
        }

        // Use binary search to efficiently find the applicable basal rate
        // Profile entries are sorted by minutes, so we can divide and conquer
        var left = 0
        var right = profile.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let entry = profile[mid]
            // Get end time for current entry - either next entry's start time or end of day (1440 mins)
            let nextMinutes = mid + 1 < profile.count ? profile[mid + 1].minutes : 1440

            // Check if target time falls within current entry's time range
            if totalMinutes >= entry.minutes, totalMinutes < nextMinutes {
                return entry.rate
            }

            // Adjust search range based on comparison
            if totalMinutes < entry.minutes {
                right = mid - 1 // Search in left half if target time is earlier
            } else {
                left = mid + 1 // Search in right half if target time is later
            }
        }

        // No applicable rate found for the given time
        return nil
    }

    /// Calculates a weighted average of Total Daily Dose (TDD) based on recent and historical data
    ///
    /// The weighted average is calculated using two time periods:
    /// - Recent: Last 2 hours of TDD data
    /// - Historical: Last 10 days of TDD data
    ///
    /// The formula used is:
    /// ```
    /// weightedTDD = (weightPercentage × recent_average) + ((1 - weightPercentage) × historical_average)
    /// ```
    /// where weightPercentage defaults to 0.65 if not set in preferences
    ///
    /// - Returns: A weighted average of TDD as Decimal, or nil if insufficient data
    /// - Note: The weight percentage can be configured in preferences. Default is 0.65 (65% recent, 35% historical)
    private func calculateWeightedAverage() async throws -> Decimal? {
        // Fetch data from Core Data
        let tenDaysAgo = Date().addingTimeInterval(-10.days.timeInterval)
        let twoHoursAgo = Date().addingTimeInterval(-2.hours.timeInterval)

        let predicate = NSPredicate(format: "date >= %@", tenDaysAgo as NSDate)

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: privateContext,
            predicate: predicate,
            key: "date",
            ascending: false
        )
        return await privateContext.perform { () -> Decimal? in
            guard let results = results as? [TDDStored], !results.isEmpty else { return 0 }

            // Calculate recent (2h) average
            let recentResults = results.filter { $0.date?.timeIntervalSince(twoHoursAgo) ?? 0 > 0 }
            let recentTotal = recentResults.compactMap { $0.total?.decimalValue }.reduce(0, +)
            let recentCount = max(Decimal(recentResults.count), 1)
            let averageTDDLastTwoHours = recentTotal / recentCount

            // Calculate 10-day average
            let totalTDD = results.compactMap { $0.total?.decimalValue }.reduce(0, +)
            let totalCount = max(Decimal(results.count), 1)
            let averageTDDLastTenDays = totalTDD / totalCount

            // Get weight percentage from preferences (default 0.65 if not set)
            let userPreferences = self.storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            let weightPercentage = userPreferences?.weightPercentage ?? Decimal(0.65) // why is this 1 as default in oref2??

            // Calculate weighted average using the formula:
            // weightedTDD = (weightPercentage × recent_average) + ((1 - weightPercentage) × historical_average)
            let weightedTDD = weightPercentage * averageTDDLastTwoHours +
                (1 - weightPercentage) * averageTDDLastTenDays

            return weightedTDD.truncated(toPlaces: 3)
        }
    }

    /// Checks if there is enough Total Daily Dose (TDD) data collected over the past 7 days.
    ///
    /// This function performs a count fetch for TDDStored records in Core Data where:
    /// - The record's date is within the last 7 days.
    /// - The total value is greater than 0.
    ///
    /// It then checks if at least 85% of the expected data points are present,
    /// assuming at least 288 expected entries per day (one every 5 minutes).
    ///
    /// - Returns: `true` if sufficient TDD data is available, otherwise `false`.
    /// - Throws: An error if the Core Data count operation fails.
    func hasSufficientTDD() async throws -> Bool {
        try await privateContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "TDDStored")
            fetchRequest.predicate = NSPredicate(
                format: "date > %@ AND total > 0",
                Date().addingTimeInterval(-86400 * 7) as NSDate
            )
            fetchRequest.resultType = .countResultType

            let count = try self.privateContext.count(for: fetchRequest)
            let threshold = Int(Double(7 * 288) * 0.85)
            return count >= threshold
        }
    }
}

/// Extension for rounding Decimal numbers
extension Decimal {
    /// Rounds a decimal to specified number of places
    /// - Parameter places: Number of decimal places
    /// - Returns: Rounded decimal
    func rounded(toPlaces places: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }

    /// Truncates the `Decimal` to the specified number of decimal places without rounding.
    ///
    /// - Parameter places: The number of decimal places to retain.
    /// - Returns: A `Decimal` truncated to the specified precision.
    func truncated(toPlaces places: Int) -> Decimal {
        var original = self
        var result = Decimal()
        NSDecimalRound(&result, &original, places, .down)
        return result
    }
}
