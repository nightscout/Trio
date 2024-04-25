import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0, *) struct tempPreset: AppEntity, Identifiable {
    static var defaultQuery = tempPresetsQuery()

    var id: UUID
    var name: String
    var targetTop: Decimal?
    var targetBottom: Decimal?
    var duration: Decimal

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Temporary Target"

    static func convert(_ tempTarget: TempTarget) -> tempPreset {
        var tp = tempPreset(
            id: UUID(uuidString: tempTarget.id)!,
            name: tempTarget.displayName,
            duration: tempTarget.duration
        )
        tp.targetTop = tempTarget.targetTop
        tp.targetBottom = tempTarget.targetBottom
        return tp
    }
}

@available(iOS 16.0, *) struct tempPresetsQuery: EntityQuery {
    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    func entities(for identifiers: [tempPreset.ID]) async throws -> [tempPreset] {
        let tempTargets = intentRequest.fetchIDs(identifiers)
        return tempTargets
    }

    func suggestedEntities() async throws -> [tempPreset] {
        let tempTargets = intentRequest.fetchAll()
        return tempTargets
    }
}
