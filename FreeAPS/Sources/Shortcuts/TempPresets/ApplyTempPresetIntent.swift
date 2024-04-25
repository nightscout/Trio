import AppIntents
import Foundation

@available(iOS 16.0, *) struct ApplyTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Apply a temporary target", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Enable a temporary target", table: "ShortcutsDetail"))

    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    @Parameter(
        title: LocalizedStringResource("Preset", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Preset choice", table: "ShortcutsDetail")
    ) var preset: tempPreset?

    @Parameter(
        title: LocalizedStringResource("Confirm Before applying", table: "ShortcutsDetail"),
        description: LocalizedStringResource("If toggled, you will need to confirm before applying", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyTempPresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$preset)", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$preset)", table: "ShortcutsDetail") {}
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
            let presetToApply: tempPreset
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchAll(),
                    dialog: IntentDialog(LocalizedStringResource("Select Temporary Target", table: "ShortcutsDetail"))
                )
            }

            let displayName: String = presetToApply.name
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(LocalizedStringResource(
                            "Confirm to apply temporary target '\(displayName)'",
                            table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            // TODO: enact the temp target
            let tempTarget = try intentRequest.findTempTarget(presetToApply)
            let finalTempTargetApply = try intentRequest.enactTempTarget(tempTarget)
            let formattedTime = decimalToTimeFormattedString(decimal: finalTempTargetApply.duration)
            return .result(
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Target '\(finalTempTargetApply.displayName)' applied for \(formattedTime)",
                        table: "ShortcutsDetail"
                    )
                )
            )
        } catch {
            throw error
        }
    }
}
