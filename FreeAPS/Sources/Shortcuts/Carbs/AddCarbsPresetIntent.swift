import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0,*) struct AddCarbPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Add Carbs", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Allow to add carbs", table: "ShortcutsDetail"))

    private var carbRequest: CarbPresetIntentRequest

    init() {
        carbRequest = CarbPresetIntentRequest()
        dateAdded = Date()
    }

    @Parameter(
        title: LocalizedStringResource("Quantity Carbs", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Quantity of carbs in g", table: "ShortcutsDetail"),
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 200),
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "What is the quantity of the carb to add ?",
            table: "ShortcutsDetail"
        ))
    ) var carbQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Quantity fat", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Quantity of fat in g", table: "ShortcutsDetail"),
        default: 0.0,
        inclusiveRange: (0, 200)
    ) var fatQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Quantity Protein", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Quantity of Protein in g", table: "ShortcutsDetail"),
        default: 0.0,
        inclusiveRange: (0, 200)
    ) var proteinQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Date", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Date of adding", table: "ShortcutsDetail")
    ) var dateAdded: Date

    @Parameter(
        title: LocalizedStringResource("Confirm Before applying", table: "ShortcutsDetail"),
        description: LocalizedStringResource("If toggled, you will need to confirm before applying", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Adding \(\.$carbQuantity) g at \(\.$dateAdded)", table: "ShortcutsDetail") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately adding \(\.$carbQuantity) g at \(\.$dateAdded)", table: "ShortcutsDetail") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let quantityCarbs: Double = carbQuantity

            let quantityCarbsName = quantityCarbs.toString()
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(LocalizedStringResource(
                            "Are you sure to add \(quantityCarbsName) g of carbs ?",
                            table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            let finalQuantityCarbsDisplay = try carbRequest.addCarbs(
                quantityCarbs: carbQuantity,
                quantityFat: fatQuantity,
                quantityProtein: proteinQuantity,
                dateAdded: dateAdded
            )
            return .result(
                dialog: IntentDialog(finalQuantityCarbsDisplay)
            )

        } catch {
            throw error
        }
    }
}
