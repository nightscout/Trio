import CoreData
import Foundation

/// Migration-specific errors that might happen during migration
enum JSONImporterError: Error {
    case missingGlucoseValueInGlucoseEntry
    case missingCarbsValueInCarbEntry
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

    /// Retrieves the set of timestamps for all carb entries currently stored in CoreData.
    ///
    /// - Parameters: the start and end dates to fetch carb entries, inclusive
    /// - Returns: A set of dates corresponding to existing carb entries.
    /// - Throws: An error if the fetch operation fails.
    private func fetchCarbEntryDates(start: Date, end: Date) async throws -> Set<Date> {
        let allCarbEntryDates = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: .predicateForDateBetween(start: start, end: end),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored] ?? []

        return Set(allCarbEntryDates.compactMap(\.date))
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
        let existingDates = try await fetchCarbEntryDates(start: twentyFourHoursAgo, end: now)

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
        carbEntry.carbs = Double(truncating: NSDecimalNumber(decimal: carbs))
        carbEntry.fat = Double(truncating: NSDecimalNumber(decimal: fat ?? 0))
        carbEntry.protein = Double(truncating: NSDecimalNumber(decimal: protein ?? 0))
        carbEntry.note = note ?? ""
        carbEntry.isFPU = false
        carbEntry.isUploadedToNS = true
        carbEntry.isUploadedToHealth = true
        carbEntry.isUploadedToTidepool = true

        if fat != nil, protein != nil, let fpuId = fpuID {
            carbEntry.fpuID = UUID(uuidString: fpuId)
        }
    }
}

extension JSONImporter {
    func importGlucoseHistoryIfNeeded() async {}
    func importCarbHistoryIfNeeded() async {}
}
