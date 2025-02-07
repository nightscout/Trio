import AppIntents
import Foundation
import Intents
import Swinject

struct TempPreset: AppEntity, Identifiable {
    static var defaultQuery = TempPresetsQuery()

    var id: UUID
    var name: String
    var targetTop: Decimal?
    var targetBottom: Decimal?
    var duration: Decimal

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Presets"
}

struct TempPresetsQuery: EntityQuery {
    func entities(for identifiers: [TempPreset.ID]) async throws -> [TempPreset] {
        await TempPresetsIntentRequest().fetchIDs(identifiers)
    }

    func suggestedEntities() async throws -> [TempPreset] {
        await TempPresetsIntentRequest().fetchAndProcessTempTargets()
    }
}
