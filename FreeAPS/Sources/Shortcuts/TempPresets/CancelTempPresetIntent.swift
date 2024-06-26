import AppIntents
import Foundation

@available(iOS 16.0, *) struct CancelTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Cancel active TempTarget", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Cancel an active TempTarget", table: "ShortcutsDetail"))

    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            if let canceledTempPresetName = try intentRequest.cancelTempTarget() {
                return .result(
                    dialog: IntentDialog(LocalizedStringResource(
                        "TempTarget '\(canceledTempPresetName)' canceled",
                        table: "ShortcutsDetail"
                    ))
                )
            } else {
                throw TempPresetsIntentRequest.TempPresetsError.noActiveTempPresets
            }

        } catch TempPresetsIntentRequest.TempPresetsError.noActiveTempPresets {
            return .result(
                dialog: IntentDialog(LocalizedStringResource("No active TempTarget to cancel", table: "ShortcutsDetail"))
            )
        } catch {
            throw error
        }
    }
}
