import AppIntents
import Foundation

struct ApplyTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Apply a Temporary Target"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Enable a Temporary Target")

    @Parameter(title: "Preset") var preset: TempPreset?

    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

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

    private func decimalToTimeFormattedString(decimal: Decimal) -> String {
        let timeInterval = TimeInterval(decimal * 60) // seconds

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .brief // example: 1h 10 min

        return formatter.string(from: timeInterval) ?? ""
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let intentRequest = TempPresetsIntentRequest()
            let presetToApply: TempPreset
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchAndProcessTempTargets(),
                    dialog: "Select Temporary Target"
                )
            }

            let displayName: String = presetToApply.name
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Confirm to apply temporary target '\(displayName)'")
                )
            }

            if await intentRequest.enactTempTarget(presetToApply) {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "TempTarget '\(presetToApply.name)' applied",
                            table: "ShortcutsDetail"
                        )
                    )
                )
            } else {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "TempTarget '\(presetToApply.name)' failed",
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
