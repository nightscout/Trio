import CoreData
import Foundation

/// Migration-specific errors that might happen during migration
enum JSONImporterError: Error {
    case missingGlucoseValueInGlucoseEntry
}

// MARK: - JSONImporter Class

/// Responsible for importing JSON data into Core Data.
///
/// The importer handles two important states:
/// - JSON files stored in the file system that contain data to import
/// - Existing entries in CoreData that should not be duplicated
///
/// Imports are performed when a JSON file exists. The importer checks
/// CoreData for existing entries to avoid duplicating records from partial imports.
class JSONImporter {
    private let context: NSManagedObjectContext
    private let coreDataStack: CoreDataStack

    /// Initializes the importer with a Core Data context.
    init(context: NSManagedObjectContext, coreDataStack: CoreDataStack) {
        self.context = context
        self.coreDataStack = coreDataStack
    }

    /// Reads and parses a JSON file from the file system.
    ///
    /// - Parameters:
    ///   - url: The URL of the JSON file to read.
    /// - Returns: A decoded object of the specified type.
    /// - Throws: An error if the file cannot be read or decoded.
    private func readJsonFile<T: Decodable>(url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONCoding.decoder
        return try decoder.decode(T.self, from: data)
    }

    /// Retrieves the set of dates for all glucose values currently stored in CoreData.
    ///
    /// - Parameters: the start and end dates to fetch glucose values, inclusive
    /// - Returns: A set of dates corresponding to existing glucose readings.
    /// - Throws: An error if the fetch operation fails.
    private func fetchGlucoseDates(start: Date, end: Date) async throws -> Set<Date> {
        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: .predicateForDateBetween(start: start, end: end),
            key: "date",
            ascending: false
        ) as? [GlucoseStored] ?? []

        return Set(allReadings.compactMap(\.date))
    }

    /// Retrieves the set of dates for all oref determinations currently stored in CoreData.
    ///
    /// - Parameters:
    ///   - start: the start to fetch from; inclusive
    ///   - end: the end date to fetch to; inclusive
    /// - Returns: A set of dates corresponding to existing determinations.
    /// - Throws: An error if the fetch operation fails.
    private func fetchDeterminationDates(start: Date, end: Date) async throws -> Set<Date> {
        let determinations = try await coreDataStack.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: .predicateForDeliverAtBetween(start: start, end: end),
            key: "deliverAt",
            ascending: false
        ) as? [OrefDetermination] ?? []

        return Set(determinations.compactMap(\.deliverAt))
    }

    /// Imports glucose history from a JSON file into CoreData.
    ///
    /// The function reads glucose data from the provided JSON file and stores new entries
    /// in CoreData, skipping entries with dates that already exist in the database.
    ///
    /// - Parameters:
    ///   - url: The URL of the JSON file containing glucose history.
    /// - Throws:
    ///   - JSONImporterError.missingGlucoseValueInGlucoseEntry if a glucose entry is missing a value.
    ///   - An error if the file cannot be read or decoded.
    ///   - An error if the CoreData operation fails.
    func importGlucoseHistory(url: URL, now: Date) async throws {
        let twentyFourHoursAgo = now - 24.hours.timeInterval
        let glucoseHistoryFull: [BloodGlucose] = try readJsonFile(url: url)
        let existingDates = try await fetchGlucoseDates(start: twentyFourHoursAgo, end: now)

        // only import glucose values from the last 24 hours that don't exist
        let glucoseHistory = glucoseHistoryFull
            .filter { $0.dateString >= twentyFourHoursAgo && $0.dateString <= now && !existingDates.contains($0.dateString) }

        // Create a background context for batch processing
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = context

        try await backgroundContext.perform {
            for glucoseEntry in glucoseHistory {
                try glucoseEntry.store(in: backgroundContext)
            }

            try backgroundContext.save()
        }

        try await context.perform {
            try self.context.save()
        }
    }

    /// Imports oref determination from a JSON file into CoreData.
    ///
    /// The function reads oref determination data from the provided JSON file and stores new entries
    /// in CoreData, skipping entries with dates that already exist in the database.
    ///
    /// - Parameters:
    ///   - url: The URL of the JSON file containing determination data.
    /// - Throws:
    ///   - JSONImporterError.missingGlucoseValueInGlucoseEntry if a glucose entry is missing a value.
    ///   - An error if the file cannot be read or decoded.
    ///   - An error if the CoreData operation fails.
    func importOrefDetermination(enactedUrl: URL, suggestedUrl: URL, now: Date) async throws {
        let twentyFourHoursAgo = now - 24.hours.timeInterval
        let enactedDetermination: Determination = try readJsonFile(url: enactedUrl)
        let suggestedDetermination: Determination = try readJsonFile(url: suggestedUrl)
        let existingDates = try await fetchDeterminationDates(start: twentyFourHoursAgo, end: now)

        /// Helper function to check if entries are from within the last 24 hours that do not yet exist in Core Data
        func checkDeterminationDate(_ date: Date) -> Bool {
            date >= twentyFourHoursAgo && date <= now && !existingDates.contains(date)
        }

        guard let enactedDeliverAt = enactedDetermination.deliverAt,
              let suggestedDeliverAt = suggestedDetermination.deliverAt
        else {
            throw JSONImporterError.missingGlucoseValueInGlucoseEntry // TODO: adjust error
        }

        guard checkDeterminationDate(enactedDeliverAt), checkDeterminationDate(suggestedDeliverAt) else {
            return
        }

        // Create a background context for batch processing
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = context

        try await backgroundContext.perform {
            /// We know both determination entries are from within last 24 hrs via the check in line 140
            /// If their `deliverAt` does not match, it is worth storing them both
            if suggestedDeliverAt != enactedDeliverAt {
                try suggestedDetermination.store(in: backgroundContext)
            }

            try enactedDetermination.store(in: backgroundContext)

            try backgroundContext.save()
        }

        try await context.perform {
            try self.context.save()
        }
    }
}

// MARK: - Extension for Specific Import Functions

extension BloodGlucose {
    /// Helper function to convert `BloodGlucose` to `GlucoseStored` while importing JSON glucose entries
    func store(in context: NSManagedObjectContext) throws {
        guard let glucoseValue = glucose ?? sgv else {
            throw JSONImporterError.missingGlucoseValueInGlucoseEntry
        }

        let glucoseEntry = GlucoseStored(context: context)
        glucoseEntry.id = _id.flatMap({ UUID(uuidString: $0) }) ?? UUID()
        glucoseEntry.date = dateString
        glucoseEntry.glucose = Int16(glucoseValue)
        glucoseEntry.direction = direction?.rawValue
        glucoseEntry.isManual = type == "Manual"
        glucoseEntry.isUploadedToNS = true
        glucoseEntry.isUploadedToHealth = true
        glucoseEntry.isUploadedToTidepool = true
    }
}

/// Extension to support decoding `Determination` entries with misspelled keys from external JSON sources.
///
/// Some legacy or third-party tools occasionally serialize the `received` property as `"recieved"`
/// (misspelled) instead of the correct `"received"`. To prevent decoding failures or data loss,
/// this custom decoder attempts to decode from `"received"` first, then falls back to `"recieved"`
/// if necessary.
///
/// Encoding always uses the correct `"received"` key to ensure consistent, standards-compliant output.
///
/// This improves resilience and ensures compatibility with imported loop history, simulations,
/// or devicestatus artifacts that may contain typos in their keys.
extension Determination: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case isf = "ISF"
        case current_target
        case tdd = "TDD"
        case insulinForManualBolus
        case manualBolusErrorString
        case minDelta
        case expectedDelta
        case minGuardBG
        case minPredBG
        case threshold
        case carbRatio = "CR"
        case received
        case receivedAlt = "recieved"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id)
        reason = try container.decode(String.self, forKey: .reason)
        units = try container.decodeIfPresent(Decimal.self, forKey: .units)
        insulinReq = try container.decodeIfPresent(Decimal.self, forKey: .insulinReq)
        eventualBG = try container.decodeIfPresent(Int.self, forKey: .eventualBG)
        sensitivityRatio = try container.decodeIfPresent(Decimal.self, forKey: .sensitivityRatio)
        rate = try container.decodeIfPresent(Decimal.self, forKey: .rate)
        duration = try container.decodeIfPresent(Decimal.self, forKey: .duration)
        iob = try container.decodeIfPresent(Decimal.self, forKey: .iob)
        cob = try container.decodeIfPresent(Decimal.self, forKey: .cob)
        predictions = try container.decodeIfPresent(Predictions.self, forKey: .predictions)
        deliverAt = try container.decodeIfPresent(Date.self, forKey: .deliverAt)
        carbsReq = try container.decodeIfPresent(Decimal.self, forKey: .carbsReq)
        temp = try container.decodeIfPresent(TempType.self, forKey: .temp)
        bg = try container.decodeIfPresent(Decimal.self, forKey: .bg)
        reservoir = try container.decodeIfPresent(Decimal.self, forKey: .reservoir)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
        isf = try container.decodeIfPresent(Decimal.self, forKey: .isf)
        current_target = try container.decodeIfPresent(Decimal.self, forKey: .current_target)
        tdd = try container.decodeIfPresent(Decimal.self, forKey: .tdd)
        insulinForManualBolus = try container.decodeIfPresent(Decimal.self, forKey: .insulinForManualBolus)
        manualBolusErrorString = try container.decodeIfPresent(Decimal.self, forKey: .manualBolusErrorString)
        minDelta = try container.decodeIfPresent(Decimal.self, forKey: .minDelta)
        expectedDelta = try container.decodeIfPresent(Decimal.self, forKey: .expectedDelta)
        minGuardBG = try container.decodeIfPresent(Decimal.self, forKey: .minGuardBG)
        minPredBG = try container.decodeIfPresent(Decimal.self, forKey: .minPredBG)
        threshold = try container.decodeIfPresent(Decimal.self, forKey: .threshold)
        carbRatio = try container.decodeIfPresent(Decimal.self, forKey: .carbRatio)

        // Handle both spellings of "received"
        if let value = try container.decodeIfPresent(Bool.self, forKey: .received) {
            received = value
        } else if let fallback = try container.decodeIfPresent(Bool.self, forKey: .receivedAlt) {
            received = fallback
        } else {
            received = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(units, forKey: .units)
        try container.encodeIfPresent(insulinReq, forKey: .insulinReq)
        try container.encodeIfPresent(eventualBG, forKey: .eventualBG)
        try container.encodeIfPresent(sensitivityRatio, forKey: .sensitivityRatio)
        try container.encodeIfPresent(rate, forKey: .rate)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(iob, forKey: .iob)
        try container.encodeIfPresent(cob, forKey: .cob)
        try container.encodeIfPresent(predictions, forKey: .predictions)
        try container.encodeIfPresent(deliverAt, forKey: .deliverAt)
        try container.encodeIfPresent(carbsReq, forKey: .carbsReq)
        try container.encodeIfPresent(temp, forKey: .temp)
        try container.encodeIfPresent(bg, forKey: .bg)
        try container.encodeIfPresent(reservoir, forKey: .reservoir)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(isf, forKey: .isf)
        try container.encodeIfPresent(current_target, forKey: .current_target)
        try container.encodeIfPresent(tdd, forKey: .tdd)
        try container.encodeIfPresent(insulinForManualBolus, forKey: .insulinForManualBolus)
        try container.encodeIfPresent(manualBolusErrorString, forKey: .manualBolusErrorString)
        try container.encodeIfPresent(minDelta, forKey: .minDelta)
        try container.encodeIfPresent(expectedDelta, forKey: .expectedDelta)
        try container.encodeIfPresent(minGuardBG, forKey: .minGuardBG)
        try container.encodeIfPresent(minPredBG, forKey: .minPredBG)
        try container.encodeIfPresent(threshold, forKey: .threshold)
        try container.encodeIfPresent(carbRatio, forKey: .carbRatio)
        try container.encodeIfPresent(received, forKey: .received) // always encode the correct spelling
    }

    /// Helper function to convert `Determination` to `OrefDetermination` while importing JSON glucose entries
    func store(in context: NSManagedObjectContext) throws {
        // TODO: some guards here ?!
        let newOrefDetermination = OrefDetermination(context: context)
        newOrefDetermination.id = UUID()
        newOrefDetermination.insulinSensitivity = decimalToNSDecimalNumber(isf)
        newOrefDetermination.currentTarget = decimalToNSDecimalNumber(current_target)
        newOrefDetermination.eventualBG = eventualBG.map(NSDecimalNumber.init)
        newOrefDetermination.deliverAt = deliverAt
        newOrefDetermination.timestamp = timestamp
        newOrefDetermination.enacted = received ?? false
        newOrefDetermination.insulinForManualBolus = decimalToNSDecimalNumber(insulinForManualBolus)
        newOrefDetermination.carbRatio = decimalToNSDecimalNumber(carbRatio)
        newOrefDetermination.glucose = decimalToNSDecimalNumber(bg)
        newOrefDetermination.reservoir = decimalToNSDecimalNumber(reservoir)
        newOrefDetermination.insulinReq = decimalToNSDecimalNumber(insulinReq)
        newOrefDetermination.temp = temp?.rawValue ?? "absolute"
        newOrefDetermination.rate = decimalToNSDecimalNumber(rate)
        newOrefDetermination.reason = reason
        newOrefDetermination.duration = decimalToNSDecimalNumber(duration)
        newOrefDetermination.iob = decimalToNSDecimalNumber(iob)
        newOrefDetermination.threshold = decimalToNSDecimalNumber(threshold)
        newOrefDetermination.minDelta = decimalToNSDecimalNumber(minDelta)
        newOrefDetermination.sensitivityRatio = decimalToNSDecimalNumber(sensitivityRatio)
        newOrefDetermination.expectedDelta = decimalToNSDecimalNumber(expectedDelta)
        newOrefDetermination.cob = Int16(Int(cob ?? 0))
        newOrefDetermination.manualBolusErrorString = decimalToNSDecimalNumber(manualBolusErrorString)
        newOrefDetermination.smbToDeliver = units.map { NSDecimalNumber(decimal: $0) }
        newOrefDetermination.carbsRequired = Int16(Int(carbsReq ?? 0))
        newOrefDetermination.isUploadedToNS = true

        if let predictions = predictions {
            ["iob": predictions.iob, "zt": predictions.zt, "cob": predictions.cob, "uam": predictions.uam]
                .forEach { type, values in
                    if let values = values {
                        let forecast = Forecast(context: context)
                        forecast.id = UUID()
                        forecast.type = type
                        forecast.date = Date()
                        forecast.orefDetermination = newOrefDetermination

                        for (index, value) in values.enumerated() {
                            let forecastValue = ForecastValue(context: context)
                            forecastValue.index = Int32(index)
                            forecastValue.value = Int32(value)
                            forecast.addToForecastValues(forecastValue)
                        }
                        newOrefDetermination.addToForecasts(forecast)
                    }
                }
        }
    }

    func decimalToNSDecimalNumber(_ value: Decimal?) -> NSDecimalNumber? {
        guard let value = value else { return nil }
        return NSDecimalNumber(decimal: value)
    }
}

extension JSONImporter {
    func importGlucoseHistoryIfNeeded() async {}
    func importDeterminationIfNeeded() async {}
}
