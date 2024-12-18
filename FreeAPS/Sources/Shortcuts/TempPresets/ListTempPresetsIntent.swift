import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListTempPresetsIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Choose Temporary Presets"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        "Allow to list and choose a specific temporary Preset.",
        categoryName: "Navigation"
    )

    @Parameter(title: "Preset") var preset: tempPreset?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the temp preset  \(\.$preset)")
    }

    @MainActor func perform() async throws -> some ReturnsValue<tempPreset> {
        .result(
            value: preset!
        )
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
