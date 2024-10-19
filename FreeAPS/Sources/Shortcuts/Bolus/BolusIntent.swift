import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0,*) struct BolusIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Enact Bolus", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Allow to send a bolus to the app", table: "ShortcutsDetail"))

    internal var bolusRequest: BolusIntentRequest

    init() {
        bolusRequest = BolusIntentRequest()
    }

    @Parameter(
        title: LocalizedStringResource("Amount", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Bolus amount in U", table: "ShortcutsDetail"),
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 200),
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "What is the value of the bolus amount in insulin units ?",
            table: "ShortcutsDetail"
        ))
    ) var bolusQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Confirm Before applying", table: "ShortcutsDetail"),
        description: LocalizedStringResource("If toggled, you will need to confirm before applying", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$bolusQuantity) U ", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$bolusQuantity) U", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let amount: Double = bolusQuantity

            let bolusFormatted = amount.formatted()
            if confirmBeforeApplying {
                let glucoseString: String = try bolusRequest.getLastBG() ?? "unknown"
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(LocalizedStringResource(
                            "Your current blood glucose is \(glucoseString). Are you sure you want to bolus \(bolusFormatted) U of insulin ?",
                            table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            let finalBolusDisplay = try bolusRequest.bolus(amount)
            return .result(
                dialog: IntentDialog(finalBolusDisplay)
            )

        } catch {
            throw error
        }
    }
}
