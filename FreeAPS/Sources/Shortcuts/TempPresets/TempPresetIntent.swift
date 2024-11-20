import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0, *) struct TempPreset: AppEntity, Identifiable {
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

//    static func convert(_ tempTarget: TempTarget) -> TempPreset {
//        var tp = TempPreset(
//            id: UUID(uuidString: tempTarget.id)!,
//            name: tempTarget.displayName,
//            duration: tempTarget.duration
//        )
//        tp.targetTop = tempTarget.targetTop
//        tp.targetBottom = tempTarget.targetBottom
//        return tp
//    }
}

struct TempPresetsQuery: EntityQuery {
    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    func entities(for identifiers: [TempPreset.ID]) async throws -> [TempPreset] {
        await intentRequest.fetchIDs(identifiers)
    }

    func suggestedEntities() async throws -> [TempPreset] {
        await intentRequest.fetchAndProcessTempTargets()
    }
}
