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

        var bolusInsulin: Decimal = 0
        var tempBasalInsulin: Decimal = 0
        var scheduledBasalInsulin: Decimal = 0

        let pumpData = calculatePumpDataHours(pumpHistory)
        debug(.apsManager, "Hours of pump data available: \(pumpData)")

        let bolusEvents = pumpHistory.filter({ $0.type == .bolus })
        let tempBasalEvents = pumpHistory.filter({ $0.type == .tempBasal })

        debug(.apsManager, "Temp basal events: \(tempBasalEvents.description)")

        let gaps = findBasalGaps(in: tempBasalEvents)
        if !gaps.isEmpty {
            scheduledBasalInsulin = calculateScheduledBasalInsulin(
                gaps: gaps,
                profile: basalProfile,
                roundToSupportedBasalRate: pumpManager.roundToSupportedBasalRate
            )
            debug(.apsManager, "Total scheduled basal insulin: \(scheduledBasalInsulin)U")
        }

        bolusInsulin = calculateBolusInsulin(bolusEvents)
        debug(.apsManager, "Total bolus insulin: \(bolusInsulin)U")

        tempBasalInsulin = calculateTempBasalInsulin(
            tempBasalEvents,
            roundToSupportedBasalRate: pumpManager.roundToSupportedBasalRate
        )
        debug(.apsManager, "Total temp basal insulin: \(tempBasalInsulin)U")

        let total = bolusInsulin + tempBasalInsulin + scheduledBasalInsulin
        let weightedAverage = await calculateWeightedAverage()

        debug(.apsManager, """
        TDD Summary:
        - Total: \(total) U
        - Bolus: \(bolusInsulin) U (\((bolusInsulin / total * 100).rounded(toPlaces: 1)) %)
        - Temp Basal: \(tempBasalInsulin) U (\((tempBasalInsulin / total * 100).rounded(toPlaces: 1)) %)
        - Scheduled Basal: \(scheduledBasalInsulin) U (\((scheduledBasalInsulin / total * 100).rounded(toPlaces: 1)) %)
        - WeightedAverage: \(weightedAverage ?? 0) U
        - Hours of Data: \(pumpData)
        """)

        return TDDResult(
            total: total,
            bolus: bolusInsulin,
            tempBasal: tempBasalInsulin,
            scheduledBasal: scheduledBasalInsulin,
            weightedAverage: weightedAverage,
            hoursOfData: pumpData
        )
    }

    /// Finds gaps between tempBasal events where scheduled basal ran
    /// - Parameter tempBasalEvents: Array of pump history events of type tempBasal
    /// - Returns: Array of gaps, where each gap has a start and end time
    private func findBasalGaps(in tempBasalEvents: [PumpHistoryEvent]) -> [(start: Date, end: Date)] {
        guard !tempBasalEvents.isEmpty else {
            // No events = full day gap
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let endOfDay = startOfDay.addingTimeInterval(24 * 60 * 60 - 1)
            return [(start: startOfDay, end: endOfDay)]
        }

        // Sort events by timestamp
        let sortedEvents = tempBasalEvents.sorted { $0.timestamp < $1.timestamp }

        var gaps: [(start: Date, end: Date)] = []

        // Track the end time of the last temp basal event
        var lastEndTime: Date?

        for (index, event) in sortedEvents.enumerated() {
            // Calculate the actual end time for the current event
            guard let duration = event.duration else { continue }
            var currentEndTime = event.timestamp.addingTimeInterval(TimeInterval(duration * 60))

            // Check for a cancellation
            if index < sortedEvents.count - 1 {
                let nextEvent = sortedEvents[index + 1]
                if nextEvent.timestamp < currentEndTime {
                    // The next event cancels this one, adjust the end time
                    currentEndTime = nextEvent.timestamp
                }
            }

            // If there’s a gap between the last event's end time and the current event's start time, record it
            if let lastEnd = lastEndTime, event.timestamp > lastEnd {
                gaps.append((start: lastEnd, end: event.timestamp))
            }

            // Update the last end time to the current event's (possibly adjusted) end time
            lastEndTime = currentEndTime
        }

        // Handle gap at the end of the dataset (if needed)
        if let lastEnd = lastEndTime {
            let endOfDay = Calendar.current.startOfDay(for: sortedEvents.first!.timestamp)
                .addingTimeInterval(24 * 60 * 60 - 1)
            if lastEnd < endOfDay {
                gaps.append((start: lastEnd, end: endOfDay))
            }
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

    /// Calculates insulin delivered via temporary basal rates, accounting for interruptions
    /// - Parameters:
    ///   - tempBasalEvents: Array of pump history events of type tempBasal
    /// - Returns: Total temporary basal insulin
    private func calculateTempBasalInsulin(
        _ tempBasalEvents: [PumpHistoryEvent],
        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    ) -> Decimal {
        guard !tempBasalEvents.isEmpty else { return Decimal(0) }

        let sortedEvents = tempBasalEvents.sorted { $0.timestamp < $1.timestamp }

        return sortedEvents.enumerated().reduce(Decimal(0)) { totalInsulin, currentEvent in
            let (index, event) = currentEvent

            // Ensure the event has valid data
            guard let rate = event.amount, // Rate in U/hr
                  let durationMinutes = event.duration, // Duration in minutes
                  rate > 0, durationMinutes > 0 else { return totalInsulin }

            // Calculate the actual duration in minutes the temp basal ran
            let actualDurationMinutes: Int
            if index < sortedEvents.count - 1 {
                // Next event exists; calculate if it interrupts the current event
                let nextEvent = sortedEvents[index + 1]
                let currentEndTime = event.timestamp.addingTimeInterval(TimeInterval(durationMinutes * 60))

                // Include a small buffer for timestamp comparison
                if nextEvent.timestamp.addingTimeInterval(-1) < currentEndTime {
                    // Interrupted; calculate the actual duration
                    let interruptedDuration = nextEvent.timestamp.timeIntervalSince(event.timestamp) / 60
                    actualDurationMinutes = max(0, Int(interruptedDuration)) // Ensure non-negative duration
                } else {
                    // Not interrupted; use full duration
                    actualDurationMinutes = durationMinutes
                }
            } else {
                // Last event in the list; calculate if it is running longer than current time
                let currentEndTime = event.timestamp.addingTimeInterval(TimeInterval(durationMinutes * 60))
                if currentEndTime > Date().addingTimeInterval(-1) {
                    let interruptedDuration = Date().timeIntervalSince(event.timestamp) / 60
                    actualDurationMinutes = max(0, Int(interruptedDuration)) // Ensure non-negative duration
                } else {
                    actualDurationMinutes = durationMinutes
                }
            }

            // Convert the duration to hours and calculate insulin
            let durationHours = Decimal(actualDurationMinutes) / 60
            let insulin = Decimal(roundToSupportedBasalRate(Double(rate * durationHours)))

            debug(
                .apsManager,
                "Temp basal: \(rate) U/hr for \(Decimal(actualDurationMinutes) / 60) hr = \(insulin) U"
            )

            return totalInsulin + insulin
        }
    }

    /// Calculates total scheduled basal insulin within gaps
    /// - Parameters:
    ///   - tempBasalEvents: Array of pump history events of type tempBasal
    ///   - profile: Array of basal profile entries
    /// - Returns: Total scheduled basal insulin
    private func calculateScheduledBasalInsulin(
        gaps: [(start: Date, end: Date)],
        profile: [BasalProfileEntry],
        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    ) -> Decimal {
        var totalInsulin: Decimal = 0

        for gap in gaps {
            var currentTime = gap.start

            while currentTime < gap.end {
                guard let rate = findBasalRate(for: getTimeString(from: currentTime), in: profile) else {
                    debug(.apsManager, "No basal rate found for time \(currentTime)")
                    break
                }

                // Determine the next switch time in the basal profile or the end of the gap
                let nextSwitchTime = getNextBasalRateSwitch(after: currentTime, in: profile) ?? gap.end
                let endTime = min(nextSwitchTime, gap.end)

                // Calculate duration in hours and insulin delivered
                let duration = Decimal(endTime.timeIntervalSince(currentTime)) / 3600
                let insulin = Decimal(roundToSupportedBasalRate(Double(rate * duration)))
                totalInsulin += insulin

                debug(.apsManager, "Scheduled basal: \(rate) U/hr from \(currentTime) to \(endTime) = \(insulin) U")

                // Move to the next time block
                currentTime = endTime
            }
        }

        return totalInsulin
    }

    /// Finds the next basal profile switch after a given time
    /// - Parameters:
    ///   - time: Current time
    ///   - profile: Array of basal profile entries
    /// - Returns: The time of the next switch, if any
    private func getNextBasalRateSwitch(after time: Date, in profile: [BasalProfileEntry]) -> Date? {
        let calendar = Calendar.current
        let timeMinutes = calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time)

        // Find the next entry in the profile after the current time
        for entry in profile {
            if entry.minutes > timeMinutes {
                let nextSwitchTime = calendar.startOfDay(for: time).addingTimeInterval(TimeInterval(entry.minutes * 60))
                return nextSwitchTime
            }
        }

        return nil // No further switches; end of day
    }

    /// Converts a Date to a time string in "HH:mm:ss" format
    private func getTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Finds the basal rate for a specific time in the profile, considering closest increments or wide coverage.
    /// - Parameters:
    ///   - timeString: Time string in "HH:mm:ss" format
    ///   - profile: Array of basal profile entries
    /// - Returns: Basal rate if found
    private func findBasalRate(for timeString: String, in profile: [BasalProfileEntry]) -> Decimal? {
        // Convert the timeString to minutes since midnight
        let timeComponents = timeString.split(separator: ":").compactMap { Int($0) }
        guard timeComponents.count == 3 else { return nil }
        let totalMinutes = timeComponents[0] * 60 + timeComponents[1]

        // If only one entry exists, return its rate (covers full 24 hours)
        guard profile.count > 1 else {
            return profile.first?.rate
        }

        // Find the closest matching basal entry
        for (index, entry) in profile.enumerated() {
            // Check if the time falls within the range of the current entry
            let startMinutes = entry.minutes
            let endMinutes = (index + 1 < profile.count) ? profile[index + 1].minutes : 1440 // End of the day

            if totalMinutes >= startMinutes, totalMinutes < endMinutes {
                return entry.rate
            }
        }

        // Default to nil if no match found
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
