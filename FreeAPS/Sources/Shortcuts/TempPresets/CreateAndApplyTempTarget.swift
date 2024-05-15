import AppIntents
import Foundation

@available(iOS 16.0, *) struct CreateAndApplyTempTarget: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Create and apply TempTarget", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description: IntentDescription = .init(.init("Create and apply a TempTarget", table: "ShortcutsDetail"))

    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    @Parameter(
        title: LocalizedStringResource("Date", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Starting Date", table: "ShortcutsDetail")
    ) var dateStart: Date?

    @Parameter(
        title: LocalizedStringResource("Glucose Target", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Glucose target in current units", table: "ShortcutsDetail"),
        controlStyle: .field,
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "What is the glucose target in current units?",
            table: "ShortcutsDetail"
        ))
    ) var target: Double

    @Parameter(
        title: LocalizedStringResource("Unit", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Glucose unit", table: "ShortcutsDetail")
    ) var unit: UnitList?

    @Parameter(
        title: LocalizedStringResource("duration", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Duration of the TempTarget", table: "ShortcutsDetail"),
        controlStyle: .field,
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "What is the duration for the TempTarget?",
            table: "ShortcutsDetail"
        ))
    ) var duration: Double

    @Parameter(
        title: LocalizedStringResource("Confirm Before applying", table: "ShortcutsDetail"),
        description: LocalizedStringResource("If toggled, you will need to confirm before applying", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Starting \(\.$target) \(\.$unit) TempTarget for \(\.$duration) min", table: "ShortcutsDetail") {
                \.$dateStart
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediatly starting \(\.$target) \(\.$unit) TempTarget for \(\.$duration) min", table: "ShortcutsDetail") {
                \.$dateStart
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

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if unit == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let targetChoice = Decimal(target)
            let durationChoice = Decimal(duration)
            let dateChoice: Date = dateStart ?? Date()

            if confirmBeforeApplying {
                let targetChoiceName = glucoseFormatter.string(from: targetChoice as NSNumber) ?? "-"
                let dateChoiceName = dateFormatter.string(from: dateChoice)
                let durationChoiceName = durationChoice.description
                let unitName = unit?.localizedStringResource ?? "-"
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(
                            LocalizedStringResource(
                                "Are you sure to create a TempTarget with \(targetChoiceName) \(unitName) for \(durationChoiceName) min at \(dateChoiceName) ?",
                                table: "ShortcutsDetail"
                            )
                        )
                    )
                )
            }

            if let finalTempTargetApply = try intentRequest.enactTempTarget(
                date: dateChoice,
                target: targetChoice,
                unit: unit,
                duration: durationChoice
            ) {
                let formattedTime = decimalToTimeFormattedString(decimal: finalTempTargetApply.duration)
                return .result(
                    dialog: IntentDialog(LocalizedStringResource(
                        "TempTarget activated for \(formattedTime)",
                        table: "ShortcutsDetail"
                    ))
                )
            } else {
                return .result(
                    dialog: IntentDialog(LocalizedStringResource("Unable to start the TempTarget", table: "ShortcutsDetail"))
                )
            }

        } catch {
            throw error
        }
    }
}
