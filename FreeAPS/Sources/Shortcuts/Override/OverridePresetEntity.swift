import AppIntents
import Foundation
import Intents
import Swinject

struct OverridePreset: AppEntity, Identifiable {
    static var defaultQuery = OverridePresetsQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Override"
}

struct OverridePresetsQuery: EntityQuery {
    func entities(for identifiers: [OverridePreset.ID]) async throws -> [OverridePreset] {
        await OverridePresetsIntentRequest().fetchIDs(identifiers)
    }

    func suggestedEntities() async throws -> [OverridePreset] {
        await OverridePresetsIntentRequest().fetchAndProcessOverrides()
    }
}
