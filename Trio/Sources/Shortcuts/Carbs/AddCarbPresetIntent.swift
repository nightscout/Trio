import AppIntents
import Foundation
import Intents
import Swinject

struct AddCarbPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Add carbs"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(LocalizedStringResource("Allow to add carbs in Trio."))

    @Parameter(
        title: "Quantity Carbs",
        description: "Quantity of carbs in g",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 300),
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "How many grams of carbs?"))
    ) var carbQuantity: Int?

    @Parameter(
        title: "Quantity Fat",
        description: "Quantity of fat in g",
        default: 0,
        inclusiveRange: (0, 300),
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "How many grams of fat?"))
    ) var fatQuantity: Int

    @Parameter(
        title: "Quantity Protein",
        description: "Quantity of Protein in g",
        default: 0,
        inclusiveRange: (0, 300),
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "How many grams of protein?"))
    ) var proteinQuantity: Int

    @Parameter(
        title: "Date",
        description: "Date of adding",
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "When did you eat ?"))
    ) var dateAdded: Date?

    @Parameter(
        title: "Notes",
        description: "Emoji or short text"
    ) var note: String?

    @Parameter(
        title: "Confirm Before Logging",
        description: "If toggled, you will need to confirm before logging",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Log \(\.$carbQuantity) at \(\.$dateAdded)") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$note
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately Log \(\.$carbQuantity) at \(\.$dateAdded)") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$note
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let quantityCarbs: Int
            if let cq = carbQuantity {
                quantityCarbs = cq
            } else {
                quantityCarbs = try await $carbQuantity.requestValue("How many grams of carbs?")
            }

            let request = CarbPresetIntentRequest()
            let maxCarbs = Int(truncating: request.settingsManager.settings.maxCarbs as NSDecimalNumber)
            let maxFat = Int(truncating: request.settingsManager.settings.maxFat as NSDecimalNumber)
            let maxProtein = Int(truncating: request.settingsManager.settings.maxProtein as NSDecimalNumber)

            guard quantityCarbs <= maxCarbs else {
                return .result(
                    dialog: IntentDialog(
                        stringLiteral: String(
                            localized: "Logging Failed: Max Carbs = \(maxCarbs) g"
                        )
                    )
                )
            }
            guard proteinQuantity <= maxProtein else {
                return .result(
                    dialog: IntentDialog(
                        stringLiteral: String(
                            localized: "Logging Failed: Max Protein = \(maxProtein) g"
                        )
                    )
                )
            }
            guard fatQuantity <= maxFat else {
                return .result(
                    dialog: IntentDialog(
                        stringLiteral: String(
                            localized: "Logging Failed: Max Fat = \(maxFat) g"
                        )
                    )
                )
            }

            let dateCarbsAdded: Date
            let dateDefinedByUser: Bool
            if let da = dateAdded {
                dateCarbsAdded = da
                dateDefinedByUser = true
            } else {
                dateCarbsAdded = Date()
                dateDefinedByUser = false
            }

            if confirmBeforeApplying {
                var confirmationMessage: String
                confirmationMessage = String(localized: "Add \(quantityCarbs) g carbs")
                if fatQuantity > 0 {
                    confirmationMessage = String(localized: "\(confirmationMessage) and \(fatQuantity) g fat")
                }
                if proteinQuantity > 0 {
                    confirmationMessage = String(localized: "\(confirmationMessage) and \(proteinQuantity) g protein")
                }
                confirmationMessage = String(localized: "\(confirmationMessage)?")

                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(stringLiteral: confirmationMessage)
                    )
                )
            }

            let finalQuantityCarbsDisplay = try await request.addCarbs(
                quantityCarbs,
                fatQuantity,
                proteinQuantity,
                dateCarbsAdded,
                note,
                dateDefinedByUser
            )
            return .result(
                dialog: IntentDialog(stringLiteral: finalQuantityCarbsDisplay)
            )

        } catch {
            throw error
        }
    }
}
