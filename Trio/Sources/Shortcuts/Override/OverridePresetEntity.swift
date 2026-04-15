import AppIntents
import Foundation
import Intents
import Swinject

/// Represents an override preset that can be used in the app.
struct OverridePreset: AppEntity, Identifiable {
    /// Default query instance for fetching override presets.
    static var defaultQuery = OverridePresetsQuery()

    /// Unique identifier for the override preset.
    var id: String

    /// Name of the override preset.
    var name: String

    /// Provides a display representation for the override preset.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    /// Representation for the entity type when displayed in UI.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Override"
}

/// Query structure for fetching override presets in an App Intent.
struct OverridePresetsQuery: EntityQuery {
    /// Fetches a list of override presets matching the given identifiers.
    ///
    /// - Parameter identifiers: A list of override preset IDs to fetch.
    /// - Returns: An array of `OverridePreset` objects matching the given IDs.
    /// - Throws: An error if the fetch operation fails.
    func entities(for identifiers: [OverridePreset.ID]) async throws -> [OverridePreset] {
        try await OverridePresetsIntentRequest().fetchIDs(identifiers)
    }

    /// Fetches a list of suggested override presets.
    ///
    /// - Returns: An array of available `OverridePreset` objects.
    /// - Throws: An error if fetching fails.
    func suggestedEntities() async throws -> [OverridePreset] {
        try await OverridePresetsIntentRequest().fetchAndProcessOverrides()
    }
}
