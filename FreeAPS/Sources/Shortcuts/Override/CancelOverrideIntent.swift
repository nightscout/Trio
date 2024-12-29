import AppIntents
import Foundation

struct CancelOverrideIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Cancel override", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Cancel an active override", table: "ShortcutsDetail"))

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            await OverridePresetsIntentRequest().cancelOverride()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Override canceled", table: "ShortcutsDetail"))
            )
        }
    }
}
