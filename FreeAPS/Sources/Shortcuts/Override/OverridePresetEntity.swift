import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0, *) struct OverridePreset: AppEntity, Identifiable {
    static var defaultQuery = OverridePresetsQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Temporary Override"
}

@available(iOS 16.0, *) struct OverridePresetsQuery: EntityQuery {
    internal var intentRequest: OverridePresetsIntentRequest

    init() {
        intentRequest = OverridePresetsIntentRequest()
    }

    func entities(for identifiers: [OverridePreset.ID]) throws -> [OverridePreset] {
        intentRequest.fetchIDs(identifiers)
    }

    func suggestedEntities() throws -> [OverridePreset] {
        intentRequest.fetchAll()
    }
}
