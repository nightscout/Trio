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

    @Parameter(title: "Preset") var preset: TempPreset?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the Temp Target preset  \(\.$preset)")
    }

    @MainActor func perform() async throws -> some ReturnsValue<TempPreset> {
        .result(
            value: preset!
        )
    }
}
