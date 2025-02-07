import AppIntents
import Foundation

struct CancelTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Cancel a Temporary Target"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Cancel Temporary Target.")

    @MainActor func perform() async throws -> some ProvidesDialog {
        await TempPresetsIntentRequest().cancelTempTarget()
        return .result(
            dialog: IntentDialog(stringLiteral: "Temporary Target canceled")
        )
    }
}
