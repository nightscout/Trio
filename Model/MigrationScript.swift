import CoreData
import Foundation

// MARK: - Protocol Definition

/// A protocol that ensures a Data Transfer Object (DTO) can be stored in Core Data.
/// It requires a method to map the DTO to its corresponding Core Data managed object.
protocol ImportableDTO: Decodable {
    associatedtype ManagedObject: NSManagedObject
    /// Converts the DTO into a Core Data managed object.
    func store(in context: NSManagedObjectContext) -> ManagedObject
}

// MARK: - JSONImporter Class with Generic Import Function

/// Class responsible for importing JSON data into Core Data.
class JSONImporter {
    private let context: NSManagedObjectContext
    private let fileManager = FileManager.default

    /// Initializes the importer with a Core Data context.
    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Generic function to import data from a JSON file into Core Data.
    /// - Parameters:
    ///   - userDefaultsKey: Key to check if data has already been imported.
    ///   - filePathComponent: Path component of the JSON file.
    ///   - dtoType: The DTO type conforming to `ImportableDTO`.
    ///   - dateDecodingStrategy: The date decoding strategy for JSON decoding.
    func importDataIfNeeded<T: ImportableDTO>(
        userDefaultsKey: String,
        filePathComponent: String,
        dtoType _: T.Type,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .iso8601
    ) async {
        let hasImported = UserDefaults.standard.bool(forKey: userDefaultsKey)

//            guard !hasImported else {
//                debugPrint("\(filePathComponent) already imported. Skipping import.")
//                return
//            }

        do {
            // Get the file path for the JSON file
            guard let filePath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(filePathComponent),
                fileManager.fileExists(atPath: filePath.path)
            else {
                debugPrint("\(DebuggingIdentifiers.failed) File not found: \(filePathComponent).")
                return
            }

            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = dateDecodingStrategy

            var entries: [T] = []

            do {
                // Decode as either an array or as a single object
                if let array = try? decoder.decode([T].self, from: data) {
                    debugPrint("\(DebuggingIdentifiers.succeeded) Decoded \(array.count) entries as an array.")
                    entries = array
                } else if let singleObject = try? decoder.decode(T.self, from: data) {
                    debugPrint("\(DebuggingIdentifiers.succeeded) Decoded a single object.")
                    entries = [singleObject]
                } else {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) Failed to decode \(filePathComponent) as either an array or a single object."
                    )
                    return
                }
            }

            // Save the DTOs into Core Data
            await context.perform {
                for entry in entries {
                    _ = entry.store(in: self.context)
                }

                do {
                    guard self.context.hasChanges else {
                        return
                    }
                    try self.context.save()
                    debugPrint("\(DebuggingIdentifiers.succeeded) \(filePathComponent) successfully imported into Core Data.")
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to save \(filePathComponent) to Core Data: \(error)")
                }
            }

            // Delete the JSON file after successful import
            try fileManager.removeItem(at: filePath)
            debugPrint("\(DebuggingIdentifiers.succeeded) \(filePathComponent) deleted after successful import.")

            // Update UserDefaults to indicate that the data has been imported
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Error importing \(filePathComponent): \(error)")
        }
    }
}

// MARK: - Extension for Specific Import Functions

extension JSONImporter {
    func importPumpHistoryIfNeeded() async {
        await importDataIfNeeded(
            userDefaultsKey: "pumpHistoryImported",
            filePathComponent: OpenAPS.Monitor.pumpHistory,
            dtoType: PumpEventDTO.self,
            dateDecodingStrategy: .iso8601
        )
    }

    func importCarbHistoryIfNeeded() async {
        await importDataIfNeeded(
            userDefaultsKey: "carbHistoryImported",
            filePathComponent: OpenAPS.Monitor.carbHistory,
            dtoType: CarbEntryDTO.self,
            dateDecodingStrategy: .iso8601
        )
    }

    func importGlucoseHistoryIfNeeded() async {
        await importDataIfNeeded(
            userDefaultsKey: "glucoseHistoryImported",
            filePathComponent: OpenAPS.Monitor.glucose,
            dtoType: GlucoseEntryDTO.self,
            dateDecodingStrategy: .iso8601
        )
    }

    func importDeterminationHistoryIfNeeded() async {
        await importDataIfNeeded(
            userDefaultsKey: "enactedHistoryImported",
            filePathComponent: OpenAPS.Enact.enacted,
            dtoType: DeterminationDTO.self,
            dateDecodingStrategy: .iso8601
        )
    }
}
