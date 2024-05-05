import AppIntents
import Foundation

@available(iOS 16.0, *) struct CancelTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Cancel a Temporary Target", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Cancel Temporary Target", table: "ShortcutsDetail"))

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
