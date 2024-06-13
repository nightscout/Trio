import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListTempPresetsIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("List TempTarget Presets", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        .init(
            "Show list and choose an existing TempTarget Preset",
            table: "ShortcutsDetail"
        )
    )

    @Parameter(
        title: LocalizedStringResource("Temporary Target", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Target choice", table: "ShortcutsDetail")
    ) var preset: TempPreset?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the TempTarget  \(\.$preset)", table: "ShortcutsDetail")
    }

    @MainActor func perform() async throws -> some ReturnsValue<TempPreset> {
        .result(
            value: preset!
        )
    }
}
