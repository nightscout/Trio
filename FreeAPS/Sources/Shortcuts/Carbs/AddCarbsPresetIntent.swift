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
        inclusiveRange: (lowerBound: 0, upperBound: 999),
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "What is the quantity of the carb to add ?",
            table: "ShortcutsDetail"
        ))
    ) var carbQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Quantity fat", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Quantity of fat in g", table: "ShortcutsDetail"),
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 999),
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "What is the quantity of the fat to add ?",
            table: "ShortcutsDetail"
        ))
    ) var fatQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Quantity Protein", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Quantity of Protein in g", table: "ShortcutsDetail"),
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 999),
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "What is the quantity of the protein to add ?",
            table: "ShortcutsDetail"
        ))
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
            Summary(
                "Adding \(\.$carbQuantity) g carbs, \(\.$fatQuantity) g fat, \(\.$proteinQuantity) g protein  at \(\.$dateAdded)",
                table: "ShortcutsDetail"
            ) {
                \.$fatQuantity
                \.$proteinQuantity
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary(
                "Immediately adding \(\.$carbQuantity) g carbs, \(\.$fatQuantity) g fat, \(\.$proteinQuantity) g protein at \(\.$dateAdded)",
                table: "ShortcutsDetail"
            ) {
                \.$fatQuantity
                \.$proteinQuantity
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let quantityCarbs: Double = carbQuantity
            let quantityCarbsAsString = String(format: "%.1f", quantityCarbs)
            let quantityFat: Double = fatQuantity
            let quantityFatAsString = String(format: "%.1f", fatQuantity)
            let quantityProtein: Double = proteinQuantity
            let quantityProteinAsString = String(format: "%.1f", proteinQuantity)
            let maxCarbs = Double(carbRequest.settingsManager.settings.maxCarbs)
            let maxCarbsAsString = String(format: "%.1f", maxCarbs)
            let maxFat = Double(carbRequest.settingsManager.settings.maxFat)
            let maxFatAsString = String(format: "%.1f", maxFat)
            let maxProtein = Double(carbRequest.settingsManager.settings.maxProtein)
            let maxProteinAsString = String(format: "%.1f", maxProtein)

            // Check if the entered carbs/fat/protein quantity exceeds the maximum allowed value
            if quantityCarbs > maxCarbs {
                let violationTypeString = "carbs"
                let violationEntryValue = maxCarbsAsString
                return .result(dialog: IntentDialog(LocalizedStringResource(
                    "No action taken. The entered quantity of \(violationTypeString) exceeds the maximum allowed limit of \(violationEntryValue) g.",
                    table: "ShortcutsDetail"
                )))
            }
            if quantityFat > maxFat {
                let violationTypeString = "fat"
                let violationEntryValue = maxFatAsString
                return .result(dialog: IntentDialog(LocalizedStringResource(
                    "No action taken. The entered quantity of \(violationTypeString) exceeds the maximum allowed limit of \(violationEntryValue) g.",
                    table: "ShortcutsDetail"
                )))
            }
            if quantityProtein > maxCarbs {
                let violationTypeString = "protein"
                let violationEntryValue = maxProteinAsString
                return .result(dialog: IntentDialog(LocalizedStringResource(
                    "No action taken. The entered quantity of \(violationTypeString) exceeds the maximum allowed limit of \(violationEntryValue) g.",
                    table: "ShortcutsDetail"
                )))
            }

            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(LocalizedStringResource(
                            "Are you sure you would like to to add \(quantityCarbsAsString) g of carbs, \(quantityFatAsString) g of fat, \(quantityProteinAsString) g of protein?",
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
