import Foundation

/// Exports meal decision records to JSON for analysis and tuning.
///
/// Each dosing decision captures the full context: macros, BG state, SmartSense breakdown,
/// computed vs. user override, and will eventually include the 8-hour post-meal trace.
enum MealDecisionExporter {
    private static let exportDirectory = "SmartSenseExports"

    /// Export a meal decision to a JSON file in the app's documents directory.
    static func export(_ decision: MealDecisionExport) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            debug(.service, "MealDecisionExporter: could not find documents directory")
            return
        }

        let exportDir = documentsURL.appendingPathComponent(exportDirectory, isDirectory: true)

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: exportDir.path) {
            do {
                try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            } catch {
                debug(.service, "MealDecisionExporter: failed to create export directory — \(error.localizedDescription)")
                return
            }
        }

        // Generate filename from dose timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "meal_\(formatter.string(from: decision.doseTimestamp)).json"
        let fileURL = exportDir.appendingPathComponent(filename)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(decision)
            try data.write(to: fileURL, options: .atomic)
            debug(.service, "MealDecisionExporter: exported \(filename) (\(data.count) bytes)")
        } catch {
            debug(.service, "MealDecisionExporter: export failed — \(error.localizedDescription)")
        }
    }

    /// List all exported meal decisions.
    static func listExports() -> [URL] {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let exportDir = documentsURL.appendingPathComponent(exportDirectory, isDirectory: true)

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: exportDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            return []
        }
    }

    /// Load a specific export.
    static func loadExport(at url: URL) -> MealDecisionExport? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MealDecisionExport.self, from: data)
        } catch {
            debug(.service, "MealDecisionExporter: failed to load \(url.lastPathComponent) — \(error.localizedDescription)")
            return nil
        }
    }
}
