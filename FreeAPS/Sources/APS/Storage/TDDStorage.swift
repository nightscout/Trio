import Foundation
import Swinject

protocol TDDStorage {
    func calculateTDD(pumpHistory: [PumpHistoryEvent], basalProfile: [BasalProfileEntry], basalIncrement: Decimal) async
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
    init(resolver: Resolver) {
        injectServices(resolver)
    }

    private let privateContext = CoreDataStack.shared.newTaskContext()

    /// Main function to calculate TDD from pump history and basal profile
    /// - Parameters:
    ///   - pumpHistory: Array of pump history events
    ///   - basalProfile: Array of basal profile entries
    /// - Returns: TDDResult containing all calculated values
    func calculateTDD(
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry],
        basalIncrement: Decimal
    ) async -> TDDResult {
        debug(.apsManager, "Starting TDD calculation with \(pumpHistory.count) pump events")

        var bolusInsulin: Decimal = 0
        var tempInsulin: Decimal = 0
        var scheduledBasalInsulin: Decimal = 0

        let pumpData = calculatePumpDataHours(pumpHistory)
        debug(.apsManager, "Hours of pump data available: \(pumpData)")

        if pumpData < 23.9, pumpData > 21 {
            let missingHours = 24 - pumpData
            debug(.apsManager, "Filling \(missingHours) missing hours with scheduled basals")
            if let lastEntry = pumpHistory.last {
                let endDate = lastEntry.timestamp
                let calculatedGapStart = endDate.addingTimeInterval(-missingHours * 3600)
                scheduledBasalInsulin = calculateScheduledBasalInsulin(
                    from: calculatedGapStart,
                    to: endDate,
                    basalProfile: basalProfile,
                    basalIncrement: basalIncrement
                )
                debug(.apsManager, "Added scheduled basal insulin: \(scheduledBasalInsulin)U")
            }
        }

        bolusInsulin = calculateBolusInsulin(pumpHistory)
        debug(.apsManager, "Total bolus insulin: \(bolusInsulin)U")

        tempInsulin = calculateTempBasalInsulin(pumpHistory, basalIncrement: basalIncrement)
        debug(.apsManager, "Total temp basal insulin: \(tempInsulin)U")

        let total = bolusInsulin + tempInsulin + scheduledBasalInsulin
        let weightedAverage = calculateWeightedAverage()

        debug(.apsManager, """
        TDD Summary:
        - Total: \(total)U
        - Bolus: \(bolusInsulin)U (\((bolusInsulin / total * 100).rounded(toPlaces: 1))%)
        - Temp Basal: \(tempInsulin)U (\((tempInsulin / total * 100).rounded(toPlaces: 1))%)
        - Scheduled Basal: \(scheduledBasalInsulin)U (\((scheduledBasalInsulin / total * 100).rounded(toPlaces: 1))%)
        - weightedAverage: \(weightedAverage ?? 0)
        - Hours of Data: \(pumpData)
        """)

        return TDDResult(
            total: total,
            bolus: bolusInsulin,
            tempBasal: tempInsulin,
            scheduledBasal: scheduledBasalInsulin,
            weightedAverage: weightedAverage,
            hoursOfData: pumpData
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

        // If last event is a temp basal, use current time
        if lastEvent.type == .tempBasalDuration {
            endDate = Date()
        }

        return Double(endDate.timeIntervalSince(startDate)) / 3600.0
    }

    /// Calculates total bolus insulin from pump history
    /// - Parameter pumpHistory: Array of pump history events
    /// - Returns: Total bolus insulin
    private func calculateBolusInsulin(_ pumpHistory: [PumpHistoryEvent]) -> Decimal {
        pumpHistory
            .filter { $0.type == .bolus }
            .reduce(Decimal(0)) { sum, event in
                sum + (event.amount ?? 0)
            }
    }

    /// Calculates insulin delivered via temporary basal rates
    /// - Parameter pumpHistory: Array of pump history events
    /// - Returns: Total temporary basal insulin
    private func calculateTempBasalInsulin(_ pumpHistory: [PumpHistoryEvent], basalIncrement: Decimal) -> Decimal {
        var totalInsulin: Decimal = 0

        for (index, event) in pumpHistory.enumerated() {
            guard event.type == .tempBasal,
                  let rate = event.amount,
                  rate > 0,
                  index > 0 else { continue }

            let duration = Decimal(pumpHistory[index - 1].duration ?? 0) / 60 // Convert to hours
            let insulin = accountForIncrements(rate * duration, basalIncrement: basalIncrement)
            totalInsulin += insulin

            debug(.apsManager, "Temp basal: \(rate)U/hr for \(duration)hr = \(insulin)U")
        }

        return totalInsulin
    }

    /// Calculates insulin delivered via scheduled basal rates
    /// - Parameters:
    ///   - from: Start date
    ///   - to: End date
    ///   - basalProfile: Array of basal profile entries
    /// - Returns: Total scheduled basal insulin
    private func calculateScheduledBasalInsulin(
        from: Date,
        to: Date,
        basalProfile: [BasalProfileEntry],
        basalIncrement: Decimal
    ) -> Decimal {
        var totalInsulin: Decimal = 0
        var currentDate = from

        while currentDate < to {
            let timeString = makeBaseString(from: currentDate)
            guard let basalRate = findBasalRate(for: timeString, in: basalProfile) else { continue }

            let nextScheduleTime = findNextScheduleTime(after: timeString, in: basalProfile)
            let durationInHours = calculateDuration(currentTime: timeString, nextScheduleTime: nextScheduleTime, endDate: to)

            let insulin = accountForIncrements(basalRate * Decimal(durationInHours), basalIncrement: basalIncrement)
            totalInsulin += insulin

            currentDate = currentDate.addingTimeInterval(durationInHours * 3600)
        }

        return totalInsulin
    }

    /// Rounds insulin amounts according to pump increment constraints
    /// - Parameter insulin: Raw insulin amount
    /// - Returns: Rounded insulin amount
    private func accountForIncrements(_ insulin: Decimal, basalIncrement: Decimal) -> Decimal {
        let incrementsRaw = insulin / basalIncrement

        if incrementsRaw >= 1 {
            // Convert to NSDecimalNumber to use its rounding capabilities
            let nsIncrements = NSDecimalNumber(decimal: incrementsRaw)
            let roundedIncrements = nsIncrements.rounding(
                accordingToBehavior:
                NSDecimalNumberHandler(
                    roundingMode: .down,
                    scale: 0,
                    raiseOnExactness: false,
                    raiseOnOverflow: false,
                    raiseOnUnderflow: false,
                    raiseOnDivideByZero: false
                )
            )
            return (roundedIncrements.decimalValue * basalIncrement).rounded(toPlaces: 3)
        }
        return 0
    }

    /// Formats a date to time string in "HH:mm:ss" format
    /// - Parameter date: Date to format
    /// - Returns: Formatted time string
    private func makeBaseString(from date: Date) -> String {
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

    /// Finds the next scheduled time in the basal profile
    /// - Parameters:
    ///   - time: Current time string
    ///   - profile: Array of basal profile entries
    /// - Returns: Next scheduled time
    private func findNextScheduleTime(after time: String, in profile: [BasalProfileEntry]) -> String {
        guard let currentIndex = profile.firstIndex(where: { $0.start == time }) else {
            return profile[0].start
        }

        let nextIndex = (currentIndex + 1) % profile.count
        return profile[nextIndex].start
    }

    /// Calculates duration between two schedule times
    /// - Parameters:
    ///   - currentTime: Current time string
    ///   - nextScheduleTime: Next schedule time string
    ///   - endDate: End date for calculations
    /// - Returns: Duration in hours
    private func calculateDuration(currentTime: String, nextScheduleTime: String, endDate _: Date) -> Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        guard let time1 = formatter.date(from: currentTime),
              let time2 = formatter.date(from: nextScheduleTime)
        else {
            return 0
        }

        var difference = time2.timeIntervalSince(time1) / 3600
        if difference < 0 {
            difference += 24
        }

        return difference
    }

    /// Calculates weighted average of TDD from historical data
    /// - Returns: Weighted average if available
    private func calculateWeightedAverage() -> Decimal? {
        // Implementation of weighted average calculation
        // Would use historical TDD data from Core Data
        nil
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
