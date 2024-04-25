import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0, *) struct overridePreset: AppEntity, Identifiable {
    static var defaultQuery = overridePresetsQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Temporary Override"
}

@available(iOS 16.0, *) struct overridePresetsQuery: EntityQuery {
    internal var intentRequest: OverridePresetsIntentRequest

    init() {
        intentRequest = OverridePresetsIntentRequest()
    }

    func entities(for identifiers: [overridePreset.ID]) throws -> [overridePreset] {
        intentRequest.fetchIDs(identifiers)
    }

    func suggestedEntities() throws -> [overridePreset] {
        intentRequest.fetchAll()
    }
}
