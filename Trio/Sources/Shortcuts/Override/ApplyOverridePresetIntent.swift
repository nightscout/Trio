import AppIntents
import Foundation

/// An App Intent that allows users to activate an override preset through the Shortcuts app.
struct ApplyOverridePresetIntent: AppIntent {
    /// The title displayed for this action in the Shortcuts app.
    static var title = LocalizedStringResource("Activate an override", table: "ShortcutsDetail")

    /// The description displayed for this action in the Shortcuts app.
    static var description = IntentDescription(.init("Activate an override", table: "ShortcutsDetail"))

    /// The override preset to be applied.
    @Parameter(
        title: LocalizedStringResource("Override", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Override choice", table: "ShortcutsDetail")
    ) var preset: OverridePreset?

    /// A boolean parameter that determines whether confirmation is required before applying the override.
    @Parameter(
        title: LocalizedStringResource("Confirm Before applying", table: "ShortcutsDetail"),
        description: LocalizedStringResource("If toggled, you will need to confirm before applying", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    /// Defines the summary format shown in the Shortcuts app when configuring this intent.
    static var parameterSummary: some ParameterSummary {
        When(\ApplyOverridePresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$preset) override", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$preset) override", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        })
    }

    /// Executes the intent to apply the selected override preset.
    ///
    /// - Returns: A dialog indicating whether the override was successfully applied or failed.
    /// - Throws: An error if an issue occurs during execution.
    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            // Determine which preset to apply
            let presetToApply: OverridePreset
            if let preset = preset {
                presetToApply = preset
            } else {
                // Request user selection if no preset is provided
                presetToApply = try await $preset.requestDisambiguation(
                    among: await OverridePresetsIntentRequest().fetchAndProcessOverrides(),
                    dialog: IntentDialog(LocalizedStringResource("Select override", table: "ShortcutsDetail"))
                )
            }

            let displayName: String = presetToApply.name

            // Request confirmation before applying if required
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(LocalizedStringResource(
                            "Confirm to apply override '\(displayName)'",
                            table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            // Apply the override and return the appropriate dialog message
            if await OverridePresetsIntentRequest().enactOverride(presetToApply) {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Override '\(presetToApply.name)' applied",
                            table: "ShortcutsDetail"
                        )
                    )
                )
            } else {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Override '\(presetToApply.name)' failed",
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
