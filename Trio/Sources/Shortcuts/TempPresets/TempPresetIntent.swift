import AppIntents
import Foundation
import Intents
import Swinject

/// Represents a temporary target preset that can be used in the app.
struct TempPreset: AppEntity, Identifiable {
    /// Default query instance for fetching temporary presets.
    static var defaultQuery = TempPresetsQuery()

    /// Unique identifier for the temporary preset.
    var id: UUID

    /// Name of the temporary preset.
    var name: String

    /// The upper target value for the preset, if applicable.
    var targetTop: Decimal?

    /// The lower target value for the preset, if applicable.
    var targetBottom: Decimal?

    /// The duration of the temporary preset in minutes.
    var duration: Decimal

    /// Provides a display representation for the temporary preset.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    /// Representation for the entity type when displayed in UI.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Presets"
}

/// Query structure for fetching temporary target presets in an App Intent.
struct TempPresetsQuery: EntityQuery {
    /// Fetches a list of temporary target presets matching the given identifiers.
    ///
    /// - Parameter identifiers: A list of preset IDs to fetch.
    /// - Returns: An array of `TempPreset` objects matching the given IDs.
    /// - Throws: An error if the fetch operation fails.
    func entities(for identifiers: [TempPreset.ID]) async throws -> [TempPreset] {
        await TempPresetsIntentRequest().fetchIDs(identifiers)
    }

    /// Fetches a list of suggested temporary target presets.
    ///
    /// - Returns: An array of available `TempPreset` objects.
    /// - Throws: An error if fetching fails.
    func suggestedEntities() async throws -> [TempPreset] {
        try await TempPresetsIntentRequest().fetchAndProcessTempTargets()
    }
}
