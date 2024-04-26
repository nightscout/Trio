import AppIntents
import Foundation

@available(iOS 16.0, *) struct ApplyOverrideIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Apply a temporary override", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Enable a temporary override", table: "ShortcutsDetail"))

    internal var intentRequest: OverridePresetsIntentRequest

    init() {
        intentRequest = OverridePresetsIntentRequest()
    }

    @Parameter(
        title: LocalizedStringResource("Preset", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Preset choice", table: "ShortcutsDetail")
    ) var preset: overridePreset?

    @Parameter(
        title: LocalizedStringResource("Confirm Before applying", table: "ShortcutsDetail"),
        description: LocalizedStringResource("If toggled, you will need to confirm before applying", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyOverrideIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$preset)", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$preset)", table: "ShortcutsDetail") {}
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let presetToApply: overridePreset
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchAll(),
                    dialog: IntentDialog(LocalizedStringResource("Select Temporary override", table: "ShortcutsDetail"))
                )
            }

            let displayName: String = presetToApply.name
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(LocalizedStringResource(
                            "Confirm to apply temporary override '\(displayName)'",
                            table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            // TODO: enact the temp target
            if try intentRequest.enactTempOverride(presetToApply) {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Target '\(presetToApply.name)' applied",
                            table: "ShortcutsDetail"
                        )
                    )
                )
            } else {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Target '\(presetToApply.name)' failed",
                            table: "ShortcutsDetail"
                        )
                    )
                )
            }

        } catch {
            throw error
        }
    }
}