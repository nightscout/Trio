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

    private let makeContext: () -> NSManagedObjectContext

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        injectServices(resolver)
    }

    /// Main function to calculate TDD from pump history
    /// - Parameters:
    ///   - pumpManager: Representation of paired pump's PumpManagerUI
    ///   - pumpHistory: Array of pump history events
    ///   - basalProfile: Schedule used to infer delivery for uncovered gaps
    /// - Returns: TDDResult containing all calculated values
    func calculateTDD(
        pumpManager: any PumpManagerUI,
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry]
    ) async throws -> TDDResult {
        debug(.algorithm, "Calculating TDD from \(pumpHistory.count) pump events")

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
        }

        let result = TDDCalculator.calculate(
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            now: Date(),
            roundToSupportedBasalRate: pumpManager.roundToSupportedBasalRate
        )
        let weighted = try await calculateWeightedAverage()
        let (hours, bolus, scheduled, temp) = (result.hoursOfData, result.bolus, result.scheduledBasal, result.tempBasal)

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

        debug(
            .algorithm,
            "TDD \(totalString) U: bolus \(bolusString) U (\(percentage(bolus, total))%), " +
                "temp basal \(tempBasalString) U (\(percentage(temp, total))%), " +
                "scheduled basal \(scheduledBasalString) U (\(percentage(scheduled, total))%), " +
                "weighted average \(weightedAvgString) U, \(hoursString) h of data, " +
                "earliest event \(earliestEvent), latest event \(latestEvent)"
        )

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
        let context = makeContext()
        context.name = "storeTDD"
        await context.perform {
            let tddStored = TDDStored(context: context)
            tddStored.id = UUID()
            tddStored.date = Date()
            tddStored.total = NSDecimalNumber(decimal: tddResult.total)
            tddStored.bolus = NSDecimalNumber(decimal: tddResult.bolus)
            tddStored.tempBasal = NSDecimalNumber(decimal: tddResult.tempBasal)
            tddStored.scheduledBasal = NSDecimalNumber(decimal: tddResult.scheduledBasal)
            tddStored.weightedAverage = tddResult.weightedAverage.map { NSDecimalNumber(decimal: $0) }

            do {
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                warning(.storage, "Saving TDD failed", error: error)
            }
        }
    }

    // The arithmetic lives in `TDDCalculator`.

    static func suspensionSpans(
        suspends: [PumpHistoryEvent],
        resumes: [PumpHistoryEvent],
        now: Date
    ) -> [(start: Date, end: Date)] {
        TDDCalculator.suspensionSpans(suspends: suspends, resumes: resumes, now: now)
    }

    func calculateTempBasalInsulin(
        _ tempBasalEvents: [PumpHistoryEvent],
        suspensions: [(start: Date, end: Date)],
        now: Date,
        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    ) -> Decimal {
        TDDCalculator.tempBasalInsulin(
            tempBasalEvents,
            suspensions: suspensions,
            now: now,
            roundToSupportedBasalRate: roundToSupportedBasalRate
        )
    }

    func calculateScheduledBasalInsulin(
        _ segments: [ScheduledBasalInference.Segment],
        roundToSupportedBasalRate: @escaping (_ unitsPerHour: Double) -> Double
    ) -> Decimal {
        TDDCalculator.scheduledBasalInsulin(segments, roundToSupportedBasalRate: roundToSupportedBasalRate)
    }

    static func timelineEvents(from pumpHistory: [PumpHistoryEvent]) -> [ScheduledBasalInference.TimelineEvent] {
        TDDCalculator.timelineEvents(from: pumpHistory)
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
        let tenDaysAgo = Date().addingTimeInterval(-10.days.timeInterval)
        let twoHoursAgo = Date().addingTimeInterval(-2.hours.timeInterval)

        let context = makeContext()
        context.name = "calculateWeightedAverage"

        return try await context.perform { () -> Decimal? in
            let recent = try Self.aggregateTDD(from: twoHoursAgo, in: context)
            let historical = try Self.aggregateTDD(from: tenDaysAgo, in: context)

            // Get weight percentage from preferences (default 0.65 if not set)
            let userPreferences = self.storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            let weightPercentage = userPreferences?.weightPercentage ?? Decimal(0.65) // why is this 1 as default in trio-oref??

            return TDDCalculator.weightedAverage(
                recentTotal: recent.total,
                recentCount: recent.count,
                tenDayTotal: historical.total,
                tenDayCount: historical.count,
                weight: weightPercentage
            )
        }
    }

    /// Runs a SUM(total) + COUNT aggregate on TDDStored for records with date >= `from`,
    /// avoiding materializing hundreds of rows just to add them up.
    private static func aggregateTDD(
        from: Date,
        in context: NSManagedObjectContext
    ) throws -> (total: Decimal, count: Int) {
        let request = NSFetchRequest<NSDictionary>(entityName: "TDDStored")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "date >= %@ AND total != nil", from as NSDate)

        let sumExp = NSExpressionDescription()
        sumExp.name = "sumTotal"
        sumExp.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "total")])
        sumExp.expressionResultType = .decimalAttributeType

        let countExp = NSExpressionDescription()
        countExp.name = "countTotal"
        countExp.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "total")])
        countExp.expressionResultType = .integer64AttributeType

        request.propertiesToFetch = [sumExp, countExp]

        guard let row = try context.fetch(request).first else {
            return (0, 0)
        }
        let sum = (row["sumTotal"] as? NSDecimalNumber)?.decimalValue ?? 0
        let count = (row["countTotal"] as? NSNumber)?.intValue ?? 0
        return (sum, count)
    }

    /// Checks if there is enough Total Daily Dose (TDD) data collected over the past 7 days.
    ///
    /// This function performs a count fetch for TDDStored records in Core Data where:
    /// - The record's date is within the last 7 days.
    /// - The total value is greater than 0.
    ///
    /// It then checks if at least 75% of the expected data points are present,
    /// assuming at least 288 expected entries per day (one every 5 minutes).
    ///
    /// - Returns: `true` if sufficient TDD data is available, otherwise `false`.
    /// - Throws: An error if the Core Data count operation fails.
    func hasSufficientTDD() async throws -> Bool {
        let context = makeContext()
        context.name = "hasSufficientTDD"
        return try await BaseTDDStorage.hasSufficientTDD(context: context)
    }

    /// internal function with context exposed to enable testing
    static func hasSufficientTDD(context: NSManagedObjectContext) async throws -> Bool {
        try await context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "TDDStored")
            fetchRequest.predicate = NSPredicate(
                format: "date > %@ AND total > 0",
                Date().addingTimeInterval(-86400 * 7) as NSDate
            )
            fetchRequest.resultType = .countResultType

            let count = try context.count(for: fetchRequest)
            return count >= TDDCalculator.sufficientRowCount
        }
    }
}
