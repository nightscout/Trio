import CoreData
import Foundation

/// Migration-specific errors that might happen during migration
enum JSONImporterError: Error {
    case missingGlucoseValueInGlucoseEntry
    case tempBasalAndDurationMismatch
    case missingRequiredPropertyInPumpEntry
    case suspendResumePumpEventMismatch
    case duplicatePumpEvents
    case missingCarbsValueInCarbEntry
    case missingRequiredPropertyInDetermination(String)
    case invalidDeterminationReason

    var errorDescription: String? {
        switch self {
        case let .missingRequiredPropertyInDetermination(field):
            return "Missing required property: \(field)"
        case .invalidDeterminationReason:
            return "Determination reason cannot be empty!"
        default:
            return nil
        }
    }
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

    /// Fetches a set of unique `Date` values for a specific `NSManagedObject` type from Core Data.
    ///
    /// This helper function is used to retrieve all existing date-like values (e.g., `date`, `timestamp`, `deliverAt`)
    /// from a given entity type within a specified time range. It wraps the fetch and transformation
    /// in a `context.perform` block to ensure thread safety when used on private background contexts.
    ///
    /// - Parameters:
    ///   - type: The `NSManagedObject` subclass to fetch (e.g., `GlucoseStored.self`, `PumpEventStored.self`)
    ///   - predicate: A preconstructed predicate that filters the entity by date/timestamp range.
    ///   - sortKey: The string name of the date-like field used to sort the fetch results. **This must match the key used in Core Data.**
    ///   - dateKeyPath: A key path pointing to the `Date?` property on the entity used to extract the actual date value from each record.
    ///
    /// - Returns: A `Set<Date>` containing all non-nil date values from the fetched entities.
    /// - Throws: `CoreDataError.fetchError` if casting the fetched objects fails, or if the fetch itself fails.

    private func fetchDates<T: NSManagedObject>(
        ofType type: T.Type,
        predicate: NSPredicate,
        sortKey: String,
        dateKeyPath: KeyPath<T, Date?>
    ) async throws -> Set<Date> {
        let fetched = try await coreDataStack.fetchEntitiesAsync(
            ofType: type,
            onContext: context,
            predicate: predicate,
            key: sortKey,
            ascending: false
        )

        return try await context.perform {
            guard let typed = fetched as? [T] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return Set(typed.compactMap { $0[keyPath: dateKeyPath] })
        }
    }

    /// Imports glucose history from a JSON file into CoreData.
    ///
    /// The function reads glucose data from the provided JSON file and stores new entries
    /// in CoreData, skipping entries with dates that already exist in the database.
    ///
    /// - Parameters:
    ///   - url: The URL of the JSON file containing glucose history.
    ///   - now: The current time, used to skip old entries
    /// - Throws:
    ///   - JSONImporterError.missingGlucoseValueInGlucoseEntry if a glucose entry is missing a value.
    ///   - An error if the file cannot be read or decoded.
    ///   - An error if the CoreData operation fails.
    func importGlucoseHistory(url: URL, now: Date) async throws {
        let twentyFourHoursAgo = now - 24.hours.timeInterval
        let glucoseHistoryFull: [BloodGlucose] = try readJsonFile(url: url)
        let existingDates = try await fetchDates(
            ofType: GlucoseStored.self,
            predicate: .predicateForDateBetween(start: twentyFourHoursAgo, end: now),
            sortKey: "date",
            dateKeyPath: \.date
        )

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

    /// combines tempBasal and tempBasalDuration events into one PumpHistoryEvent
    private func combineTempBasalAndDuration(pumpHistory: [PumpHistoryEvent]) throws -> [PumpHistoryEvent] {
        let tempBasal = pumpHistory.filter({ $0.type == .tempBasal }).sorted { $0.timestamp < $1.timestamp }
        let tempBasalDuration = pumpHistory.filter({ $0.type == .tempBasalDuration }).sorted { $0.timestamp < $1.timestamp }
        let nonTempBasal = pumpHistory.filter { $0.type != .tempBasal && $0.type != .tempBasalDuration }

        guard tempBasal.count == tempBasalDuration.count else {
            throw JSONImporterError.tempBasalAndDurationMismatch
        }

        let combinedTempBasal = try zip(tempBasal, tempBasalDuration).map { rate, duration in
            guard rate.timestamp == duration.timestamp else {
                throw JSONImporterError.tempBasalAndDurationMismatch
            }
            return PumpHistoryEvent(
                id: duration.id,
                type: .tempBasal,
                timestamp: duration.timestamp,
                duration: duration.durationMin,
                rate: rate.rate,
                temp: rate.temp
            )
        }

        return (combinedTempBasal + nonTempBasal).sorted { $0.timestamp < $1.timestamp }
    }

    /// checks for pumpHistory inconsistencies that might cause issues if we import these events into CoreData
    private func checkForInconsistencies(pumpHistory: [PumpHistoryEvent]) throws {
        // make sure that pump suspends / resumes match up
        let suspendsAndResumes = pumpHistory.filter({ $0.type == .pumpSuspend || $0.type == .pumpResume })
            .sorted { $0.timestamp < $1.timestamp }

        for (current, next) in zip(suspendsAndResumes, suspendsAndResumes.dropFirst()) {
            guard current.type != next.type else {
                throw JSONImporterError.suspendResumePumpEventMismatch
            }
        }

        // check for duplicate events
        struct TypeTimestamp: Hashable {
            let timestamp: Date
            let type: EventType
        }

        let duplicates = Dictionary(grouping: pumpHistory) { TypeTimestamp(timestamp: $0.timestamp, type: $0.type) }
            .values.first(where: { $0.count > 1 })

        if duplicates != nil {
            throw JSONImporterError.duplicatePumpEvents
        }
    }

    /// Imports pump history from a JSON file into CoreData.
    ///
    /// The function reads pump history data from the provided JSON file and stores new entries
    /// in CoreData, skipping entries with timestamps that already exist in the database.
    ///
    /// - Parameters:
    ///   - url: The URL of the JSON file containing pump history.
    ///   - now: The current time, used to skip old entries
    /// - Throws:
    ///   - JSONImporterError.tempBasalAndDurationMismatch if we can't match tempBasals with their duration.
    ///   - An error if the file cannot be read or decoded.
    ///   - An error if the CoreData operation fails.
    func importPumpHistory(url: URL, now: Date) async throws {
        let twentyFourHoursAgo = now - 24.hours.timeInterval
        let pumpHistoryRaw: [PumpHistoryEvent] = try readJsonFile(url: url)
        let existingTimestamps = try await fetchDates(
            ofType: PumpEventStored.self,
            predicate: .predicateForTimestampBetween(start: twentyFourHoursAgo, end: now),
            sortKey: "timestamp",
            dateKeyPath: \.timestamp
        )
        let pumpHistoryFiltered = pumpHistoryRaw
            .filter { $0.timestamp >= twentyFourHoursAgo && $0.timestamp <= now && !existingTimestamps.contains($0.timestamp) }

        let pumpHistory = try combineTempBasalAndDuration(pumpHistory: pumpHistoryFiltered)
        try checkForInconsistencies(pumpHistory: pumpHistory)

        // Create a background context for batch processing
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = context

        try await backgroundContext.perform {
            for pumpEntry in pumpHistory {
                try pumpEntry.store(in: backgroundContext)
            }

            try backgroundContext.save()
        }

        try await context.perform {
            try self.context.save()
        }
    }

    /// Imports carb history from a JSON file into CoreData.
    ///
    /// The function reads carb entries data from the provided JSON file and stores new entries
    /// in CoreData, skipping entries with dates that already exist in the database.
    /// We ignore all FPU entries (aka carb equivalents) when performing an import.
    ///
    /// - Parameters:
    ///   - url: The URL of the JSON file containing glucose history.
    ///   - now: The current datetime
    /// - Throws:
    ///   - JSONImporterError.missingCarbsValueInCarbEntry if a carb entry is missing a `carbs: Decimal` value.
    ///   - An error if the file cannot be read or decoded.
    ///   - An error if the CoreData operation fails.
    func importCarbHistory(url: URL, now: Date) async throws {
        let twentyFourHoursAgo = now - 24.hours.timeInterval
        let carbHistoryFull: [CarbsEntry] = try readJsonFile(url: url)
        let existingDates = try await fetchDates(
            ofType: CarbEntryStored.self,
            predicate: .predicateForDateBetween(start: twentyFourHoursAgo, end: now),
            sortKey: "date",
            dateKeyPath: \.date
        )

        // Only import carb entries from the last 24 hours that do not exist yet in Core Data
        // Only import "true" carb entries; ignore all FPU entries (aka carb equivalents)
        let carbHistory = carbHistoryFull
            .filter {
                let dateToCheck = $0.actualDate ?? $0.createdAt
                return dateToCheck >= twentyFourHoursAgo && dateToCheck <= now && !existingDates.contains(dateToCheck) && $0
                    .isFPU ?? false == false }

        // Create a background context for batch processing
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = context

        try await backgroundContext.perform {
            for carbEntry in carbHistory {
                try carbEntry.store(in: backgroundContext)
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
        let existingDates = try await fetchDates(
            ofType: OrefDetermination.self,
            predicate: .predicateForDeliverAtBetween(start: twentyFourHoursAgo, end: now),
            sortKey: "deliverAt",
            dateKeyPath: \.deliverAt
        )

        /// Helper function to check if entries are from within the last 24 hours that do not yet exist in Core Data
        func checkDeterminationDate(_ date: Date) -> Bool {
            date >= twentyFourHoursAgo && date <= now && !existingDates.contains(date)
        }

        guard let enactedDeliverAt = enactedDetermination.deliverAt,
              let suggestedDeliverAt = suggestedDetermination.deliverAt
        else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("deliverAt")
        }

        guard checkDeterminationDate(enactedDeliverAt), checkDeterminationDate(suggestedDeliverAt) else {
            return
        }

        try enactedDetermination.checkForRequiredFields()
        try suggestedDetermination.checkForRequiredFields()

        // Create a background context for batch processing
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = context

        try await backgroundContext.perform {
            /// We know both determination entries are from within last 24 hrs via `checkDeterminationDate()` in the earlier `guard` clause
            /// If their `deliverAt` does not match, and if `suggestedDeliverAt` is newer, it is worth storing them both, as that represents
            /// a more recent algorithm run that did not cause a dosing enactment, e.g., a carb entry or a manual bolus.
            if suggestedDeliverAt > enactedDeliverAt {
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

extension PumpHistoryEvent {
    /// Helper function to convert `PumpHistoryEvent` to `PumpEventStored` while importing JSON pump histories
    func store(in context: NSManagedObjectContext) throws {
        let pumpEntry = PumpEventStored(context: context)
        pumpEntry.id = id
        pumpEntry.timestamp = timestamp
        pumpEntry.type = type.rawValue
        pumpEntry.isUploadedToNS = true
        pumpEntry.isUploadedToHealth = true
        pumpEntry.isUploadedToTidepool = true

        if type == .bolus {
            guard let amount = amount else {
                throw JSONImporterError.missingRequiredPropertyInPumpEntry
            }
            let bolusEntry = BolusStored(context: context)
            bolusEntry.amount = NSDecimalNumber(decimal: amount)
            bolusEntry.isSMB = isSMB ?? false
            bolusEntry.isExternal = isExternal ?? isExternalInsulin ?? false
            pumpEntry.bolus = bolusEntry
        } else if type == .tempBasal {
            guard let rate = rate, let duration = duration else {
                throw JSONImporterError.missingRequiredPropertyInPumpEntry
            }
            let tempEntry = TempBasalStored(context: context)
            tempEntry.rate = NSDecimalNumber(decimal: rate)
            tempEntry.duration = Int16(duration)
            tempEntry.tempType = temp?.rawValue
            pumpEntry.tempBasal = tempEntry
        }
    }
}

/// Extension to support decoding `CarbsEntry` from JSON with multiple possible key formats for entry notes.
///
/// This is needed because some JSON sources (e.g., Trio v0.2.5) use the singular key `"note"`
/// for the `note` field, while others (e.g., Nightscout or oref) use the plural `"notes"`.
///
/// To ensure compatibility across all sources without duplicating models or requiring upstream fixes,
/// this custom implementation attempts to decode the `note` field first from `"note"`, then from `"notes"`.
/// Encoding will always use the canonical `"notes"` key to preserve consistency in output,
/// as this is what's established throughout the backend now.
extension CarbsEntry: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        actualDate = try container.decodeIfPresent(Date.self, forKey: .actualDate)
        carbs = try container.decode(Decimal.self, forKey: .carbs)
        fat = try container.decodeIfPresent(Decimal.self, forKey: .fat)
        protein = try container.decodeIfPresent(Decimal.self, forKey: .protein)

        // Handle both `note` and `notes`
        if let noteValue = try? container.decodeIfPresent(String.self, forKey: .note) {
            note = noteValue
        } else if let notesValue = try? container.decodeIfPresent(String.self, forKey: .noteAlt) {
            note = notesValue
        } else {
            note = nil
        }

        enteredBy = try container.decodeIfPresent(String.self, forKey: .enteredBy)
        isFPU = try container.decodeIfPresent(Bool.self, forKey: .isFPU)
        fpuID = try container.decodeIfPresent(String.self, forKey: .fpuID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(actualDate, forKey: .actualDate)
        try container.encode(carbs, forKey: .carbs)
        try container.encodeIfPresent(fat, forKey: .fat)
        try container.encodeIfPresent(protein, forKey: .protein)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(enteredBy, forKey: .enteredBy)
        try container.encodeIfPresent(isFPU, forKey: .isFPU)
        try container.encodeIfPresent(fpuID, forKey: .fpuID)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt = "created_at"
        case actualDate
        case carbs
        case fat
        case protein
        case note = "notes" // standard key
        case noteAlt = "note" // import key
        case enteredBy
        case isFPU
        case fpuID
    }

    /// Helper function to convert `CarbsStored` to `CarbEntryStored` while importing JSON carb entries
    func store(in context: NSManagedObjectContext) throws {
        guard carbs >= 0 else {
            throw JSONImporterError.missingCarbsValueInCarbEntry
        }

        // skip FPU entries for now

        let carbEntry = CarbEntryStored(context: context)
        carbEntry.id = id
            .flatMap({ UUID(uuidString: $0) }) ?? UUID() /// The `CodingKey` of `id` is `_id`, so this fine to use here
        carbEntry.date = actualDate ?? createdAt
        carbEntry.carbs = Double(truncating: NSDecimalNumber(decimal: carbs.rounded(toPlaces: 0)))
        carbEntry.fat = Double(truncating: NSDecimalNumber(decimal: fat?.rounded(toPlaces: 0) ?? 0))
        carbEntry.protein = Double(truncating: NSDecimalNumber(decimal: protein?.rounded(toPlaces: 0) ?? 0))
        carbEntry.note = note ?? ""
        carbEntry.isFPU = false
        carbEntry.isUploadedToNS = true
        carbEntry.isUploadedToHealth = true
        carbEntry.isUploadedToTidepool = true
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

    func checkForRequiredFields() throws {
        guard let deliverAt = deliverAt else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("deliverAt")
        }
        guard let timestamp = timestamp else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("timestamp")
        }
        guard reason.isNotEmpty else {
            throw JSONImporterError.invalidDeterminationReason
        }
        guard let insulinReq = insulinReq else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("insulinReq")
        }
        guard let currentTarget = current_target else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("current_target")
        }
        guard let reservoir = reservoir else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("reservoir")
        }
        guard let threshold = threshold else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("threshold")
        }
        guard let iob = iob else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("IOB")
        }
        guard let isf = isf else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("ISF")
        }
        guard let manualBolusErrorString = manualBolusErrorString else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("manualBolusErrorString")
        }
        guard let insulinForManualBolus = insulinForManualBolus else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("insulinForManualBolus")
        }
        guard let cob = cob else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("COB")
        }
        guard let tdd = tdd else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("TDD")
        }
        guard let bg = bg else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("bg")
        }
        guard let minDelta = minDelta else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("minDelta")
        }
        guard let eventualBG = eventualBG else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("eventualBG")
        }
        guard let sensitivityRatio = sensitivityRatio else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("sensitivityRatio")
        }
        guard let temp = temp else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("temp")
        }
        guard let expectedDelta = expectedDelta else {
            throw JSONImporterError.missingRequiredPropertyInDetermination("expectedDelta")
        }
    }

    /// Helper function to convert `Determination` to `OrefDetermination` while importing JSON glucose entries
    func store(in context: NSManagedObjectContext) throws {
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
    private func openAPSFileURL(_ relativePath: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(relativePath)
    }

    func importGlucoseHistoryIfNeeded() async throws {
        debug(.coreData, "Checking for glucose history JSON file...")

        let url = openAPSFileURL(OpenAPS.Monitor.glucose)
        let suffix = "migrated.json"

        guard FileManager.default.fileExists(atPath: url.path) else {
            debug(.coreData, "❌ No JSON file to import at \(url.path)")
            return
        }

        debug(.coreData, "Glucose history JSON file found, proceeding with import of glucose history...")

        try await importGlucoseHistory(url: url, now: Date())

        debug(.coreData, "Glucose history JSON file imported successfully, moving to \(suffix)")

        try FileManager.default.moveItem(
            at: url,
            to: url.deletingPathExtension().appendingPathExtension(suffix)
        )

        debug(.coreData, "Import of glucose history completed successfully.")
    }

    func importPumpHistoryIfNeeded() async throws {
        debug(.coreData, "Checking for pump history JSON file...")

        let url = openAPSFileURL(OpenAPS.Monitor.pumpHistory)
        let suffix = "migrated.json"

        guard FileManager.default.fileExists(atPath: url.path) else {
            debug(.coreData, "❌ No JSON file to import at \(url.path)")
            return
        }

        debug(.coreData, "Pump history JSON file found, proceeding with import of glucose history...")

        try await importPumpHistory(url: url, now: Date())

        debug(.coreData, "Pump history JSON file imported successfully, moving to \(suffix)")

        try FileManager.default.moveItem(
            at: url,
            to: url.deletingPathExtension().appendingPathExtension(suffix)
        )

        debug(.coreData, "Import of pump history completed successfully.")
    }

    func importCarbHistoryIfNeeded() async throws {
        debug(.coreData, "Checking for carb history JSON file...")

        let url = openAPSFileURL(OpenAPS.Monitor.carbHistory)
        let suffix = "migrated.json"

        guard FileManager.default.fileExists(atPath: url.path) else {
            debug(.coreData, "❌ No JSON file to import at \(url.path)")
            return
        }

        debug(.coreData, "Carb history JSON file found, proceeding with import of glucose history...")

        try await importCarbHistory(url: url, now: Date())

        debug(.coreData, "Carb history JSON file imported successfully, moving to \(suffix)")

        try FileManager.default.moveItem(
            at: url,
            to: url.deletingPathExtension().appendingPathExtension(suffix)
        )

        debug(.coreData, "Import of carb history completed successfully.")
    }

    func importDeterminationIfNeeded() async throws {
        debug(.coreData, "Checking for determination JSON files...")

        let enactedPath = OpenAPS.Enact.enacted // "enact/enacted.json"
        let suggestedPath = OpenAPS.Enact.suggested // "enact/suggested.json"
        let suffix = "migrated.json"

        let enactedURL = openAPSFileURL(enactedPath)
        let suggestedURL = openAPSFileURL(suggestedPath)

        guard FileManager.default.fileExists(atPath: enactedURL.path),
              FileManager.default.fileExists(atPath: suggestedURL.path)
        else {
            debug(.coreData, "❌ No JSON file to import at \(enactedURL.path) and/or \(suggestedURL.path)")
            return
        }

        debug(.coreData, "Determination JSON files found, proceeding with import...")

        try await importOrefDetermination(enactedUrl: enactedURL, suggestedUrl: suggestedURL, now: Date())

        debug(.coreData, "Determination JSON file(s) imported successfully, moving to \(suffix)")

        try FileManager.default.moveItem(at: enactedURL, to: enactedURL.deletingPathExtension().appendingPathExtension(suffix))
        try FileManager.default.moveItem(
            at: suggestedURL,
            to: suggestedURL.deletingPathExtension().appendingPathExtension(suffix)
        )

        debug(.coreData, "Import of determination data completed successfully.")
    }
}
