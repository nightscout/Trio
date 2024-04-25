import AppIntents
import Foundation

@available(iOS 16.0, *) struct CancelOverrideIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Cancel a override preset", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Cancel a override preset", table: "ShortcutsDetail"))

    internal var intentRequest: OverridePresetsIntentRequest

    init() {
        intentRequest = OverridePresetsIntentRequest()
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            try intentRequest.cancelTempTarget()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Temporary Override canceled", table: "ShortcutsDetail"))
            )
        } catch {
            throw error
        }
    }
}
