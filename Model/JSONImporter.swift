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
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(T.self, from: data)
    }

    /// Retrieves the set of dates for all glucose values currently stored in CoreData.
    ///
    /// - Returns: A set of dates corresponding to existing glucose readings.
    /// - Throws: An error if the fetch operation fails.
    private func fetchGlucoseDates() async throws -> Set<Date> {
        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
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
    func importGlucoseHistory(url: URL) async throws {
        let glucoseHistory: [Glucose] = try readJsonFile(url: url)
        let existingDates = try await fetchGlucoseDates()
        for glucoseEntry in glucoseHistory {
            if !existingDates.contains(glucoseEntry.date) {
                try glucoseEntry.store(in: context)
            }
        }
    }
}

// MARK: - Extension for Specific Import Functions

extension JSONImporter {
    func importGlucoseHistoryIfNeeded() async {}
}
