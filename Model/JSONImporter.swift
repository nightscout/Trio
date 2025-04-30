import CoreData
import Foundation

/// Migration-specific errors that might happen during migration
enum JSONImporterError: Error {
    case missingGlucoseValueInGlucoseEntry
    case tempBasalAndDurationMismatch
    case missingRequiredPropertyInPumpEntry
    case suspendResumePumpEventMismatch
    case duplicatePumpEvents
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

    /// Retrieves the set of timestamps for all pump evets currently stored in CoreData.
    ///
    /// - Parameters: the start and end dates to fetch pump events, inclusive
    /// - Returns: A set of dates corresponding to existing pump events.
    /// - Throws: An error if the fetch operation fails.
    private func fetchPumpTimestamps(start: Date, end: Date) async throws -> Set<Date> {
        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: .predicateForTimestampBetween(start: start, end: end),
            key: "timestamp",
            ascending: false
        ) as? [PumpEventStored] ?? []

        return Set(allReadings.compactMap(\.timestamp))
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
        let existingTimestamps = try await fetchPumpTimestamps(start: twentyFourHoursAgo, end: now)
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
            bolusEntry.isExternal = isExternal ?? false
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

extension JSONImporter {
    func importGlucoseHistoryIfNeeded() async {}
}
