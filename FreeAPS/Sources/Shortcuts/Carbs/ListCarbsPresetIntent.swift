import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListCarbsPresetsIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("List Carbs presets", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        .init(
            "Allow to list and collect carbs, fats, proteins for a carb preset",
            table: "ShortcutsDetail"
        )
    )

    internal var carbRequest: CarbPresetIntentRequest

    init() {
        carbRequest = CarbPresetIntentRequest()
    }

    @Parameter(
        title: LocalizedStringResource("Carbs Preset", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Carbs Preset selection", table: "ShortcutsDetail")
    ) var preset: carbPresetResult?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the Carb preset \(\.$preset)", table: "ShortcutsDetail")
    }

    @MainActor func perform() async throws -> some ReturnsValue<carbPresetResult?>
    {
        //     if let id = preset?.id, let presetChoice = try carbRequest.getCarbsPresetInfo(presetId: id) {
        if let presetChoice = preset {
            return .result(
                value: presetChoice
            )
        } else {
            return .result(
                value: nil
            )
        }
    }
}
