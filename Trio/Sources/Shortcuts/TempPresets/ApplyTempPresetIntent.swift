import AppIntents
import Foundation

/// An App Intent that allows users to apply a temporary target preset through the Shortcuts app.
struct ApplyTempPresetIntent: AppIntent {
    /// The title displayed for this action in the Shortcuts app.
    static var title: LocalizedStringResource = "Apply a Temporary Target"

    /// The description displayed for this action in the Shortcuts app.
    static var description = IntentDescription("Enable a Temporary Target")

    /// The temporary target preset to be applied.
    @Parameter(title: "Preset") var preset: TempPreset?

    /// A boolean parameter that determines whether confirmation is required before applying the temporary target.
    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

    /// Defines the summary format shown in the Shortcuts app when configuring this intent.
    static var parameterSummary: some ParameterSummary {
        When(\ApplyTempPresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        })
    }

    /// Converts a decimal duration value into a formatted time string.
    ///
    /// - Parameter decimal: The duration value in decimal format.
    /// - Returns: A string representing the formatted time in hours and minutes.
    private func decimalToTimeFormattedString(decimal: Decimal) -> String {
        let timeInterval = TimeInterval(decimal * 60) // Convert minutes to seconds

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .brief // Example: "1h 10m"

        return formatter.string(from: timeInterval) ?? ""
    }

    /// Executes the intent to apply the selected temporary target preset.
    ///
    /// - Returns: A dialog indicating whether the temporary target was successfully applied or failed.
    /// - Throws: An error if an issue occurs during execution.
    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let intentRequest = TempPresetsIntentRequest()
            let presetToApply: TempPreset

            // Determine which preset to apply
            if let preset = preset {
                presetToApply = preset
            } else {
                // Request user selection if no preset is provided
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchAndProcessTempTargets(),
                    dialog: "Select Temporary Target"
                )
            }

            let displayName: String = presetToApply.name

            // Request confirmation before applying if required
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Confirm to apply Temporary Target '\(displayName)'")
                )
            }

            // Apply the temporary target and return the appropriate dialog message
            if await intentRequest.enactTempTarget(presetToApply) {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Temporary Target '\(presetToApply.name)' applied"
                        )
                    )
                )
            } else {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Temporary Target '\(presetToApply.name)' failed"
                        )
                    )
                )
            }
        } catch {
            throw error
        }
    }
}
