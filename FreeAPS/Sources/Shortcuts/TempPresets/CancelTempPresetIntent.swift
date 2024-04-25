import AppIntents
import Foundation

@available(iOS 16.0, *) struct CancelTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Cancel a temporary Preset", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Cancel temporary preset", table: "ShortcutsDetail"))

    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            try intentRequest.cancelTempTarget()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Temporary Target canceled", table: "ShortcutsDetail"))
            )
        } catch {
            throw error
        }
    }
}
