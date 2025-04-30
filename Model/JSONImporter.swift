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
}

// MARK: - Extension for Specific Import Functions

extension BloodGlucose {
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

extension JSONImporter {
    func importGlucoseHistoryIfNeeded() async {}
}
