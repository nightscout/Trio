import Foundation
import LoopKitUI
import Swinject

protocol TDDStorage {
    func calculateTDD(pumpManager: any PumpManagerUI, pumpHistory: [PumpHistoryEvent], basalProfile: [BasalProfileEntry]) async
        -> TDDResult
    func storeTDD(_ tddResult: TDDResult) async
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

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    private let privateContext = CoreDataStack.shared.newTaskContext()

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
    ) async -> TDDResult {
        debug(.apsManager, "Starting TDD calculation with \(pumpHistory.count) pump events")

        // Group events by type once to avoid multiple filters
        let groupedEvents = Dictionary(grouping: pumpHistory, by: { $0.type })
        let bolusEvents = groupedEvents[.bolus] ?? []
        let tempBasalEvents = groupedEvents[.tempBasal] ?? []

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
            tempBasalEvents,
            roundToSupportedBasalRate: pumpManager.roundToSupportedBasalRate
        )

        async let weightedAverage = calculateWeightedAverage()

        // Await all concurrent calculations
        let (hours, bolus, scheduled, temp, weighted) = await (
            pumpDataHours,
            bolusInsulin,
            scheduledBasalInsulin,
            tempBasalInsulin,
            weightedAverage
        )

        let total = bolus + temp + scheduled

        debug(.apsManager, """
        TDD Summary:
        - Total: \(total) U
        - Bolus: \(bolus) U (\((bolus / total * 100).rounded(toPlaces: 1)) %)
        - Temp Basal: \(temp) U (\((temp / total * 100).rounded(toPlaces: 1)) %)
        - Scheduled Basal: \(scheduled) U (\((scheduled / total * 100).rounded(toPlaces: 1)) %)
        - WeightedAverage: \(weighted ?? 0) U
        - Hours of Data: \(hours)
        """)

        return TDDResult(
            total: total,
            bolus: bolus,
            tempBasal: temp,
            scheduledBasal: scheduled,
            weightedAverage: weighted,
            hoursOfData: hours
        )
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
                debug(.apsManager, "\(DebuggingIdentifiers.failed) Failed to save TDD: \(error.localizedDescription)")
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
                totalBolusInsulin + (event.amount ?? 0)
            }
    }

    /// Calculates temporary basal insulin delivery for a given time period
    /// - Parameters:
    ///   - tempBasalEvents: Array of temporary basal events sorted by timestamp
    ///   - roundToSupportedBasalRate: Closure to round rates to pump-supported values
    /// - Returns: Total insulin delivered via temporary basal rates in units
    private func calculateTempBasalInsulin(
        _ tempBasalEvents: [PumpHistoryEvent],
        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    ) -> Decimal {
        guard !tempBasalEvents.isEmpty else { return 0 }

        let sortedEvents = tempBasalEvents.sorted { $0.timestamp < $1.timestamp }
        let currentDate = Date()

        return sortedEvents.enumerated().reduce(into: Decimal(0)) { totalInsulin, currentEvent in
            let (index, event) = currentEvent

            // Validate required event data (rate and duration)
            guard let rate = event.amount,
                  let durationMinutes = event.duration,
                  rate > 0, durationMinutes > 0
            else { return }

            let actualDurationMinutes: Int

            if index < sortedEvents.count - 1 {
                // Handle interruption by subsequent temp basal
                let nextEvent = sortedEvents[index + 1]
                let currentEndTime = event.timestamp.addingTimeInterval(TimeInterval(durationMinutes * 60))

                actualDurationMinutes = nextEvent.timestamp.addingTimeInterval(-1) < currentEndTime
                    ? max(0, Int(nextEvent.timestamp.timeIntervalSince(event.timestamp) / 60))
                    : durationMinutes
            } else {
                // Handle currently running temp basal
                let currentEndTime = event.timestamp.addingTimeInterval(TimeInterval(durationMinutes * 60))
                actualDurationMinutes = currentEndTime > currentDate.addingTimeInterval(-1)
                    ? max(0, Int(currentDate.timeIntervalSince(event.timestamp) / 60))
                    : durationMinutes
            }

            // Calculate and accumulate insulin delivery
            let durationHours = Decimal(actualDurationMinutes) / 60
            let insulin = Decimal(roundToSupportedBasalRate(Double(rate * durationHours)))

            totalInsulin += insulin
        }
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

                let endTime = min(nextSwitchTime, gap.end)
                let duration = Decimal(endTime.timeIntervalSince(currentTime)) / 3600

                totalInsulin += Decimal(roundToSupportedBasalRate(Double(rate * duration)))
                currentTime = endTime
            }
        }
    }

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
    private func calculateWeightedAverage() async -> Decimal? {
        // Fetch data from Core Data
        let tenDaysAgo = Date().addingTimeInterval(-10.days.timeInterval)
        let twoHoursAgo = Date().addingTimeInterval(-2.hours.timeInterval)

        let predicate = NSPredicate(format: "date >= %@", tenDaysAgo as NSDate)

        let results = await CoreDataStack.shared.fetchEntitiesAsync(
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

            return weightedTDD
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
}
