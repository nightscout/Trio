import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0,*) struct AddCarbPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Add carbs"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Allow to add carbs in Trio.")

    init() {
        dateAdded = Date()
    }

    @Parameter(
        title: "Quantity Carbs",
        description: "Quantity of carbs in g",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 200),
        requestValueDialog: IntentDialog("What is the numeric value of the carb to add")
    ) var carbQuantity: Double?

    @Parameter(
        title: "Quantity fat",
        description: "Quantity of fat in g",
        default: 0.0,
        inclusiveRange: (0, 200)
    ) var fatQuantity: Double

    @Parameter(
        title: "Quantity Protein",
        description: "Quantity of Protein in g",
        default: 0.0,
        inclusiveRange: (0, 200)
    ) var proteinQuantity: Double

    @Parameter(
        title: "Date",
        description: "Date of adding"
    ) var dateAdded: Date

    @Parameter(
        title: "Notes",
        description: "Emoji or short text"
    ) var note: String?

    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$carbQuantity) at \(\.$dateAdded)") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$note
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$carbQuantity) at \(\.$dateAdded)") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$note
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let quantityCarbs: Double
            if let cq = carbQuantity {
                quantityCarbs = cq
            } else {
                quantityCarbs = try await $carbQuantity.requestValue("How many carbs ?")
            }

            let quantityCarbsName = quantityCarbs.toString()
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure to add \(quantityCarbsName) g of carbs ?")
                )
            }

            let finalQuantityCarbsDisplay = try await CarbPresetIntentRequest().addCarbs(
                quantityCarbs,
                fatQuantity,
                proteinQuantity,
                dateAdded,
                note
            )
            return .result(
                dialog: IntentDialog(stringLiteral: finalQuantityCarbsDisplay)
            )

        } catch {
            throw error
        }
    }
}
