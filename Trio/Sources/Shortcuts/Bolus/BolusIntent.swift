import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0,*) struct BolusIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Enact Bolus")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Allow to send a bolus to the app"))

    @Parameter(
        title: LocalizedStringResource("Amount"),
        description: LocalizedStringResource("Bolus amount in U"),
        controlStyle: .field,
        /// The 200 upperBound does nothing here, the true max is set based on pump max
        /// An upperBound is specificed so that we can usethe lowerBound of 0, which ensures no negatives are allowed
        /// A preferred approach would be to just block negatives and not specify an upperBound here, since it is implemented elsewhere
        inclusiveRange: (lowerBound: 0, upperBound: 200),
        requestValueDialog: IntentDialog(
            stringLiteral: String(
                localized:
                "Bolus amount (units of insulin)?"
            )
        )
    ) var bolusQuantity: Double

    @Parameter(
        title: LocalizedStringResource("External Insulin"),
        description: LocalizedStringResource("If toggled, Insulin will be added to IOB but it will not be delivered"),
        default: false,
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "External Insulin?"))
    ) var externalInsulin: Bool

    @Parameter(
        title: LocalizedStringResource("Confirm Before applying"),
        description: LocalizedStringResource("If toggled, you will need to confirm before applying."),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$externalInsulin, .equalTo, true, {
            Summary("Log external insulin bolus \(\.$bolusQuantity) U") {
                \.$externalInsulin
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            When(\.$confirmBeforeApplying, .equalTo, true, {
                Summary("Applying \(\.$bolusQuantity) U") {
                    \.$externalInsulin
                    \.$confirmBeforeApplying
                }
            }, otherwise: {
                Summary("Immediately applying \(\.$bolusQuantity) U") {
                    \.$externalInsulin
                    \.$confirmBeforeApplying
                }
            })
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let amount: Double = bolusQuantity

            let bolusFormatted = amount.formatted()
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(
                            stringLiteral: String(
                                localized:
                                externalInsulin ? "Are you sure to log \(bolusFormatted) U of external insulin?" :
                                    "Are you sure to bolus \(bolusFormatted) U of insulin?"
                            )
                        )
                    )
                )
            }
            if externalInsulin {
                let finalExternalBolusDisplay = try await BolusIntentRequest().bolusExternal(amount)
                return .result(
                    dialog: IntentDialog(stringLiteral: finalExternalBolusDisplay)
                )
            } else {
                let finalBolusDisplay = try await BolusIntentRequest().bolus(amount)
                return .result(
                    dialog: IntentDialog(stringLiteral: finalBolusDisplay)
                )
            }
        } catch {
            throw error
        }
    }
}
