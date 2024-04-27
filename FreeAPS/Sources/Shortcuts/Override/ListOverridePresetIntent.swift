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
        title: LocalizedStringResource("Temporary Override", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Override choice", table: "ShortcutsDetail")
    ) var preset: overridePreset?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the temporary override  \(\.$preset)", table: "ShortcutsDetail")
    }

    @MainActor func perform() async throws -> some ReturnsValue<overridePreset> {
        .result(
            value: preset!
        )
    }
}
