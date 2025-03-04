import AppIntents
import Foundation

/// An App Intent that allows users to cancel an active override through the Shortcuts app.
struct CancelOverrideIntent: AppIntent {
    /// The title displayed for this action in the Shortcuts app.
    static var title = LocalizedStringResource("Cancel override", table: "ShortcutsDetail")

    /// The description displayed for this action in the Shortcuts app.
    static var description = IntentDescription(.init("Cancel an active override", table: "ShortcutsDetail"))

    /// Performs the intent action to cancel an active override.
    ///
    /// - Returns: A confirmation dialog indicating the override has been canceled.
    /// - Throws: An error if the cancellation process fails.
    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            await OverridePresetsIntentRequest().cancelOverride()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Override canceled", table: "ShortcutsDetail"))
            )
        }
    }
}
