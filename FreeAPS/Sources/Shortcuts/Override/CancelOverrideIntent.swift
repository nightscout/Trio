import AppIntents
import Foundation

@available(iOS 16.0, *) struct CancelOverrideIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Cancel an active Override", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Cancel an active Override", table: "ShortcutsDetail"))

    internal var intentRequest: OverridePresetsIntentRequest

    init() {
        intentRequest = OverridePresetsIntentRequest()
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            if let cancelledOverrideName = try intentRequest.cancelOverride() {
                return .result(
                    dialog: IntentDialog(LocalizedStringResource(
                        "Override '\(cancelledOverrideName)' canceled",
                        table: "ShortcutsDetail"
                    ))
                )
            } else {
                throw OverridePresetsIntentRequest.overridePresetsError.noActiveOverride
            }
        } catch OverridePresetsIntentRequest.overridePresetsError.noActiveOverride {
            return .result(
                dialog: IntentDialog(LocalizedStringResource("No active Override to cancel", table: "ShortcutsDetail"))
            )
        } catch {
            throw error
        }
    }
}
