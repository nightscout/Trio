import AppIntents
import Foundation

@available(iOS 16.0, *) struct ApplyTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Apply a temporary target"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Enable a temporary target")

    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    @Parameter(title: "Preset") var preset: tempPreset?

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
            let presetToApply: tempPreset
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchAll(),
                    dialog: "Select Temporary Target"
                )
            }

            let displayName: String = presetToApply.name
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Confirm to apply temporary target '\(displayName)'")
                )
            }

            // TODO: enact the temp target
            let tempTarget = try intentRequest.findTempTarget(presetToApply)
            let finalTempTargetApply = try intentRequest.enactTempTarget(tempTarget)
            let formattedTime = decimalToTimeFormattedString(decimal: finalTempTargetApply.duration)
            let displayDetail: String =
                "Target '\(finalTempTargetApply.displayName)' applied for \(formattedTime)"
            return .result(
                dialog: IntentDialog(stringLiteral: displayDetail)
            )
        } catch {
            throw error
        }
    }
}
