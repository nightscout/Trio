import CoreData
import Foundation

@available(iOS 16.0,*) final class CarbPresetIntentRequest: BaseIntentsRequest {
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    func addCarbs(
        _ quantityCarbs: Double,
        _ quantityFat: Double,
        _ quantityProtein: Double,
        _ dateAdded: Date
    ) throws -> LocalizedStringResource {
        guard quantityCarbs >= 0.0 || quantityFat >= 0.0 || quantityProtein >= 0.0 else {
            return LocalizedStringResource("no adding carbs", table: "ShortcutsDetail")
        }

        let carbs = min(Decimal(quantityCarbs), settingsManager.settings.maxCarbs)

        carbsStorage.storeCarbs(
            [CarbsEntry(
                id: UUID().uuidString,
                createdAt: dateAdded,
                carbs: carbs,
                fat: Decimal(quantityFat),
                protein: Decimal(quantityProtein),
                note: "add with shortcuts",
                enteredBy: CarbsEntry.manual,
                isFPU: (quantityFat > 0 || quantityProtein > 0) ? true : false,
                fpuID: (quantityFat > 0 || quantityProtein > 0) ? UUID().uuidString : nil
            )]
        )
        let dateName = dateAdded.formatted()
        let carbsFormatted = numberFormatter.string(from: carbs as NSNumber) ?? "0"
        let fatsFormatted = numberFormatter.string(from: quantityFat as NSNumber) ?? "0"
        let proteinsFormatted = numberFormatter.string(from: quantityProtein as NSNumber) ?? "0"
        return LocalizedStringResource(
            " \(carbsFormatted) g carbs and \(fatsFormatted) g fats and \(proteinsFormatted) g protein added at \(dateName)",
            table: "ShortcutsDetail"
        )
    }
}
