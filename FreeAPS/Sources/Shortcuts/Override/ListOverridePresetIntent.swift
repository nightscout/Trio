import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListOverridePresetsIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("List Temporary Override", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        .init(
            "Allow to list and choose a specific temporary override",
            table: "ShortcutsDetail"
        )
    )

    @Parameter(
        title: LocalizedStringResource("Preset", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Preset choice", table: "ShortcutsDetail")
    ) var preset: overridePreset?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the temp preset  \(\.$preset)", table: "ShortcutsDetail")
    }

    @MainActor func perform() async throws -> some ReturnsValue<overridePreset> {
        .result(
            value: preset!
        )
    }
}
