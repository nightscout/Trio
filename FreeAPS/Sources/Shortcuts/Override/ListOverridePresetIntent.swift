import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListOverridePresetsIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("List overrides", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        .init(
            "Allow to list and choose a specific override",
            table: "ShortcutsDetail"
        )
    )

    @Parameter(
        title: LocalizedStringResource("Override", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Override choice", table: "ShortcutsDetail")
    ) var preset: OverridePreset?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the Override  \(\.$preset)", table: "ShortcutsDetail")
    }

    @MainActor func perform() async throws -> some ReturnsValue<OverridePreset> {
        .result(
            value: preset!
        )
    }
}
